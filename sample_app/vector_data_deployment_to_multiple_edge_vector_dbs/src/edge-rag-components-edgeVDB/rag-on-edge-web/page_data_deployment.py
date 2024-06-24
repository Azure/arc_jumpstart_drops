import streamlit as st
import requests

FUNCTION_URL  = "<Replace with your actual Azure Function URL>" 

st.title('Deploy Cloud Vector Data to Edge VDB')
st.write('**Please select an existing index name or input an index name with that you want to deploy the data and update the vector content.**')
# Option for the user to select
option = st.radio("Choose an option:", ('Select an existing index name', 'Input an index name'))
if option == 'Select an existing index name':
    with st.spinner(text="Loading..."):
        backend_url = 'http://rag-vdb-service:8602/list_index_names'  
        index_names = requests.get(backend_url).json()['index_names']
        index_name_restore = st.selectbox('Please select an index name.',index_names)
        st.write('You selected:', index_name_restore)

elif option == 'Input an index name':
    # restore backup file to update the local VDB content with the cloud VDB embeddings
    index_name_restore = st.text_input('Input an index name:')
    st.write('You input:', index_name_restore)

st.markdown("<br><br>", unsafe_allow_html=True)  # Adds blank lines

if st.button('Update Index Contents'):
    if index_name_restore == '':
        st.error('Please input index name for updating the vector content!')
        st.stop()
    else:
        with st.spinner('Updating index contents...'):
            update_url = 'http://rag-vdb-service:8602/restore_index_contents_backupfile'  # Replace with your actual backend URL if needed
            payload = {'index_name': index_name_restore}
            response = requests.post(update_url, json=payload)

            if response.status_code == 200:
                st.success(f"{response.json()['message']}")
            else:
                st.error(f"Failed to update index contents. Error: {response.text}")


st.markdown("<br><br><br><br>", unsafe_allow_html=True)  # Adds blank lines
st.write('**For demo of triggering cloud indexing**')
st.write('Below is only for demo of triggering cloud indexing: chunk and vectorize the documents in Azure Blob, and store the vector data into the cloud VectorDB master.')
st.write('The doc pre-stored in Az Blob used for demo: Benefit_Options.pdf')
index_name_cloud = st.text_input('Input an index name to store in the cloud VDB:')
st.write('You input:', index_name_cloud)
if st.button('Cloud Indexing'):
    doc_info_list = [
        {"name": "Benefit_Options.pdf", "url": f"https://textdatasource.blob.core.windows.net/pdf-set1/Benefit_Options.pdf?sp=r&st=2024-05-06T01:43:51Z&se=2025-05-06T09:43:51Z&spr=https&sv=2022-11-02&sr=b&sig=Kg33yIF4jnvOCrLC2V93%2FeetfwZmJ0vbz3H6%2B1XV2Y8%3D", "index": index_name_cloud}
        # {"name": "employee_handbook.pdf", "url": f"https://textdatasource.blob.core.windows.net/pdf-set1/employee_handbook.pdf?sp=r&st=2024-05-06T01:55:21Z&se=2025-05-06T09:55:21Z&spr=https&sv=2022-11-02&sr=b&sig=UYP0rl52k3s7QGbmtyqWDNJcheyureDfV%2B35pMZ5050%3D", "index": index_name_cloud},
        # {"name": "role_library.pdf", "url": f"https://textdatasource.blob.core.windows.net/pdf-set1/role_library.pdf?sp=r&st=2024-05-06T01:55:56Z&se=2025-05-06T09:55:56Z&spr=https&sv=2022-11-02&sr=b&sig=MjgKAZuJLhOKGzV19WNco870T95xWUumDxXNu6t%2FhNA%3D", "index": index_name_cloud}
    ]
    for doc_info in doc_info_list:
        doc_name = doc_info["name"]
        doc_url = doc_info["url"]
        index_name = doc_info["index"]
        headers = {
            "Content-Type": "application/json"
        }
        payload = {
            "doc_name": doc_name,
            "doc_url": doc_url,
            "index_name": index_name
        }
        # Trigger Azure Function
        response = requests.post(FUNCTION_URL, json=payload, headers=headers)
        if response.status_code == 200:
            st.success(f"Azure Function Response: {response.text}")
            print(f"Azure Function Response: {response.text}")
        else:
            st.error(f"Failed to trigger Azure Function: {response.text}")
            print(f"Failed to trigger Azure Function: {response.text}")
