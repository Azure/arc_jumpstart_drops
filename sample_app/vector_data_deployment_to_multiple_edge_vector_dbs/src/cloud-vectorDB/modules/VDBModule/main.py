'''this module will do the following:
cloud Chroma as a DB leader hosted in Cloud VM.
az fxn send chunked text data to cloud Chroma.
text data will be vectorized by Chroma's embedding model, and stored in Chroma
'''
from flask import Flask, request, jsonify
import json
import os
import logging
from function.ChromaHelper import ChromaHelper
from azure.storage.blob import BlobServiceClient, BlobClient, ContainerClient

logging.basicConfig(level=logging.DEBUG)

# Initialize the BlobServiceClient with your Azure Storage connection string
VECTOR_DATA_SOURCE_STORAGE_CONNECTION_STRING = f""
CONTAINER_NAME = "rag-vdb" # replace with your container name of the blob storage for storing the embeddings data

#subscriber using Dapr PubSub
app = Flask(__name__)
app_port = os.getenv('VDB_PORT', '8602')

chromaHelper = ChromaHelper()

def chroma_db_backup(index_name):
    # retrieve chromaDB vector data by retrieving chromaDB backup file
    retrieved_embeddings = chromaHelper.retrieve_embeddings(index_name)
    
    # send the embeddings data to blob storage
    BLOB_NAME = f"retrieved_embeddings-{index_name}.json"
    # Convert the embeddings data to JSON format
    embeddings_json = json.dumps(retrieved_embeddings)
    # Create a BlobServiceClient
    blob_service_client = BlobServiceClient.from_connection_string(VECTOR_DATA_SOURCE_STORAGE_CONNECTION_STRING)
    # Get a ContainerClient
    container_client = blob_service_client.get_container_client(CONTAINER_NAME)
    # Ensure the container exists
    try:
        container_client.create_container()
    except Exception as e:
        logging.info(f"Container already exists: {e}")
    # Get a BlobClient
    blob_client = container_client.get_blob_client(BLOB_NAME)
    # Upload the embeddings JSON data to the blob
    try:
        blob_client.upload_blob(embeddings_json, overwrite=True)
        logging.info(f"Embeddings data uploaded successfully to {BLOB_NAME} in container {CONTAINER_NAME}.")
    except Exception as e:
        logging.error(f"Failed to upload embeddings data to blob storage: {e}")

    return retrieved_embeddings


# APIs for receiving http request from the frontend web app
@app.route('/list_index_names', methods=['GET'])
def list_index_names():
    index_names = chromaHelper.list_index_names()
    return jsonify({'status': 'success', 'message': 'index name list is retrieved', 'index_names': index_names})

@app.route('/create_index', methods=['POST'])
def create_index():
    data = request.json
    index_name = data.get('index_name')
    if not index_name:
        return jsonify({'status': 'error', 'message': 'Index name not provided'}), 400
    try:
        chromaHelper.create_index(index_name)
        return jsonify({'status': 'success', 'message': 'Index created successfully'})
    except Exception as e:
        return jsonify({'status': 'error', 'message': f'Error creating index: {str(e)}'}), 500

@app.route('/delete_index', methods=['POST'])
def delete_index():
    data = request.json
    index_name = data.get('index_name')
    if not index_name:
        return jsonify({'status': 'error', 'message': 'Index name not provided'}), 400
    try:
        chromaHelper.delete_index(index_name)
        return jsonify({'status': 'success', 'message': 'Index deleted successfully'})
    except Exception as e:
        return jsonify({'status': 'error', 'message': f'Error deleting index: {str(e)}'}), 500
    
@app.route('/upload_file', methods=['POST'])
def upload_file():
    try :
        data = request.json
        if not data:
            return jsonify({'status': 'error', 'message': 'Invalid payload.'}), 400        
        index_name = data.get('index_name')
        ids = data.get('ids_list') 
        documents = data.get('documents_list')

        # check if index_name exists. if not, create an index with the index_name
        index_names_list = chromaHelper.list_index_names()
        if index_name not in index_names_list:
            try: 
                chromaHelper.create_index(index_name)
            except Exception as e:
                return jsonify({'status': 'error', 'message': f'Error creating index {index_name}: {str(e)}'}), 500
        new_index_names_list = chromaHelper.list_index_names()

        try:
            chromaHelper.upload_documents(index_name, ids, documents)
            logging.info(f"Documents uploaded successfully to the index {index_name} of the cloud Chroma master.")
        except Exception as e:
            logging.info(f"Error uploading documents to index {index_name}: {str(e)}")
            return jsonify({'status': 'error', 'message': f'Error uploading documents to index {index_name}: {str(e)}'}), 500

        # retrieve the vector data from the index/collection, and send the vector data to blob storage
        chroma_db_backup(index_name)
        return jsonify({'status': 'success', 'message': 'The chunked items are vectorized and uploaded to Chroma master successfully. The embeddings data of the index is backed up to blob storage.'})
    except Exception as e:
        return jsonify({'status': 'error', 'message': f'Error uploading file: {str(e)}'}), 500 


if __name__ == '__main__':
    #app.run(port=app_port)
    app.run(host='0.0.0.0', port=app_port)

