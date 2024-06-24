import chromadb
import os  
import logging


num_search_results = 1
class ChromaHelper:    
    def __init__(self):
        current_path = os.getcwd()    
        self.data_path = current_path+"/chromedb/db"

    def delete_index(self, index_name):
        # Delete a search index
        client = chromadb.PersistentClient(path=self.data_path)
        result = client.delete_collection(index_name)
        return result
    
    def create_index(self, index_name):
        client = chromadb.PersistentClient(path=self.data_path)
        collection = client.get_or_create_collection(
        name=index_name,
        metadata={"hnsw:space": "cosine"} # l2 is the default
        )
        return collection
    
    def list_index_names(self):
        client = chromadb.PersistentClient(path=self.data_path)
        index_names = client.list_collections()
        collection_names = [collection.name for collection in client.list_collections()]  
        return collection_names
    
    def upload_documents(self, index_name, ids, documents):
        # it will convert documents to embeddings by default embedding model all-MiniLM-L6-v2
        client = chromadb.PersistentClient(path=self.data_path)
        collection = client.get_collection(name=index_name)
        result = collection.add(
                                documents=documents,
                                ids=ids
                            )
        return result
    
    def similarity_search(self, index_name, search_text):
        client = chromadb.PersistentClient(path=self.data_path)
        collection = client.get_collection(name=index_name)
        return collection.query(
            query_texts=[search_text],
            n_results=num_search_results,
        )
    def retrieve_embeddings(self, index_name):
        client = chromadb.PersistentClient(path=self.data_path)
        collection = client.get_collection(name=index_name)
        return collection.get(include=["documents", "embeddings", "metadatas"])

    def restore_embeddings(self, index_name, ids, embeddings, documents, metadatas):
        client = chromadb.PersistentClient(path=self.data_path)
        collection = client.get_collection(name=index_name)
        return collection.add(ids=ids, embeddings=embeddings, documents = documents, metadatas=metadatas)
