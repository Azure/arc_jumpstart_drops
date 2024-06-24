import requests

FUNCTION_URL  = "<Azure Function URL>" # replace with your Azure Function URL

def trigger_azure_function(doc_name, doc_url, index_name):
    # Request headers
    headers = {
        "Content-Type": "application/json"
    }

    # Request payload
    payload = {
        "doc_name": doc_name,
        "doc_url": doc_url,
        "index_name": index_name
    }

    # Trigger Azure Function
    response = requests.post(FUNCTION_URL, json=payload, headers=headers)

    # Check if request was successful
    if response.status_code == 200:
        print("Azure Function triggered successfully")
        print(f"Azure Function Response: {response.text}")
    else:
        print(f"Failed to trigger Azure Function: {response.text}")

if __name__ == "__main__":
    # Example usage
    doc_info_list = [
        {"name": "Benefit_Options.pdf", "url": f"<>", "index": "test-index"},
        {"name": "employee_handbook.pdf", "url": f"<>", "index": "test-index"},
        {"name": "role_library.pdf", "url": f"<>", "index": "test-index"}
    ]

    for doc_info in doc_info_list:
        doc_name = doc_info["name"]
        doc_url = doc_info["url"]
        index_name = doc_info["index"]
        trigger_azure_function(doc_name, doc_url, index_name)


