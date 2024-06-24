import io
import azure.functions as func
import logging
from azure.storage.blob import BlobServiceClient
from function.NormalizeText import NormalizeText
from function.LangChainChunking import LangChanSplitter
import pandas as pd
import numpy as np
import uuid
import requests
 
DATA_SOURCE_STORAGE_CONNECTION_STRING=f"" # replace with the connection string of the blob storage for the files you want to chunk
DATA_SOURCE_STORAGE_CONTAINER_NAME=f""  # replace with the container name of the blob storage 
CHROMA_DB_URL = "http://<chroma leader's host machine IP>:8602/upload_file" # replace with the host machine IP of the chroma leader

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

@app.route(route="http_trigger_chunking")
def http_trigger_chunking(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Python HTTP trigger function processed a request.')
    try:
        req_body = req.get_json()
    except ValueError:
        return func.HttpResponse(
             "Invalid request payload.",
             status_code=400
        )

    doc_name = req_body.get('doc_name')
    doc_url = req_body.get('doc_url')
    index_name = req_body.get('index_name')
   
    if doc_name and doc_url and index_name:
        #pull doc file from the blob storage
        blob_service_client = BlobServiceClient.from_connection_string(DATA_SOURCE_STORAGE_CONNECTION_STRING)
        blob_client = blob_service_client.get_blob_client(container=DATA_SOURCE_STORAGE_CONTAINER_NAME, blob=doc_name)
        pdf_file = io.BytesIO() # load into a stream
        num_bytes = blob_client.download_blob().readinto(pdf_file)

        # read pdf file
        pdf_reader = NormalizeText()
        longtxt = pdf_reader.get_doc_content_txt(pdf_file)
        len_longtxt=len(longtxt)

        pdf_reader = LangChanSplitter()
        stringlist = pdf_reader.TokenTextSplitter(100,10,longtxt)
        len_stringlist=len(stringlist)
        
        df = pd.DataFrame({'document': stringlist})
        df = df.dropna() 
        df['id'] = df.apply(lambda x : str(uuid.uuid4()), axis=1)  

        # split df to 50 records per batch
        df_array = np.array_split(df, len(df) // 50 + 1)  

        # To push chunked items to VDB in azure VM
        data_array_count = len(df_array)
        new_df_array = []
        current_job_number = 1
        for sub_df in df_array:
            logging.info("working on: " + str(current_job_number) + "/" +str(data_array_count))
            documents_list = sub_df["document"].to_list()
            ids_list = sub_df["id"].to_list()  

            response = requests.post(CHROMA_DB_URL, json={"ids_list": ids_list, "documents_list": documents_list, "index_name": index_name})

            if response.status_code != 200:
                logging.error(f"Failed to upload chunk to Chroma DB: {response.content}")
                return func.HttpResponse(
                    f"Failed to upload chunk to Chroma DB: {current_job_number}: {response.content}",
                    status_code=response.status_code,
                )
            new_df_array.append(sub_df)
            current_job_number+=1
        new_df = pd.concat(new_df_array, axis=0, ignore_index=True) 
        logging.info(str(len(new_df)) + " chunked items are uploaded to Chroma leader.")
        
        return func.HttpResponse(
            f"Payload {doc_name} received, and the chunked items are sent to Chroma leader successfully.",
            status_code=200
        )
    else:
        return func.HttpResponse(
             "Missing required parameters in the payload.",
            status_code=400
        )
