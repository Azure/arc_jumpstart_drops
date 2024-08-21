# Cerebral Implementation Guide

## Introduction

Cerebral is an innovative smart assistant tailored for industrial applications, specifically designed to enhance operational efficiency at Contoso Motors. This solution leverages advanced Generative AI technology to interact with factory workers using natural language, making it intuitive and user-friendly. Cerebral’s core aim is to streamline decision-making processes and reduce downtime by providing immediate access to critical information and operational insights.

### Key Features and Benefits

- **Natural Language Processing**: At the heart of Cerebral is its ability to understand and process queries in natural language. This allows plant workers to ask complex questions about machine operations, maintenance schedules, or troubleshooting steps as if they were speaking to a human expert.

- **Dynamic Information Access**: Depending on the nature of the query, Cerebral can search through extensive databases of manuals and guidelines to provide troubleshooting assistance or access real-time data directly from the production line’s equipment and sensors. This ensures that the information provided is not only accurate but also timely and relevant.

- **Hybrid Model Utilization**: The architecture of Cerebral incorporates both cloud-based and on-premises components, including the use of Open AI for cloud-based computations and an on-premises SLM for handling sensitive data locally. This hybrid approach ensures optimal balance between performance and security, adhering to industry best practices for data governance. 

- **Enhanced Decision Making**: Through its integration with advanced data analytics platforms like Azure Data Explorer, Cerebral offers powerful visualization tools that help users identify trends, analyze performance metrics, and make well-informed decisions faster than ever before.

- **Customizable and Scalable**: The system is designed to be flexible, supporting modifications and enhancements to meet the evolving needs of Contoso Motors. It can scale across different departments and adapt to various industrial environments without significant alterations to the core system.

### Target Audience

Cerebral is specifically developed for operational technology professionals including mechanics, maintenance staff, and production line managers. It simplifies their daily tasks by providing a seamless interface to query operational data, access procedural documents, and gain insights into machinery health and performance.

This smart assistant is not just a tool but a part of the team, designed to work alongside factory personnel to enhance productivity and ensure that the manufacturing processes at Contoso Motors are as efficient as possible.

By integrating Cerebral, Contoso Motors aims to set a new standard in industrial operations, focusing on connectivity, speed, and intelligence. The upcoming sections will detail the technical architecture, setup instructions, and operational guidelines to fully leverage Cerebral’s capabilities in a manufacturing setting.


## Architecture

## Cerebral Architecture Overview

The architecture of Cerebral integrates various components to provide a robust solution for real-time data processing and query handling within an industrial setting. The system is designed to be deployed on a factory-floor located, Arc-enabled AKS Edge Essentials cluster, ensuring that both data security and processing efficiency are optimized.

### Key Components

1. **OT Frontline Worker Interface**:
   - This is the primary user interface where operational technology (OT) frontline workers, such as mechanics, maintenance personnel, or plan managers, interact with the Cerebral system. Users can input their queries in natural language, which are then processed by the system to fetch relevant information or perform actions.

2. **Redis Cache**:
   - Utilized as a caching layer to store temporary data which may include session states and conversations.

3. **Web Application**:
   - Hosts the user interface and the agent responsible for classifying questions based on the input received from the OT frontline worker.

4. **Classify Agent**:
   - Analyzes the questions to determine the type of query and routes it to the appropriate processing path, either pulling data from real-time systems or fetching documents.

5. **Query Processing Orchestrator**:
   - Manages the workflow of data queries and document retrievals, ensuring that requests are processed efficiently and correctly routed to either InfluxDB for data-related queries or the Chroma vector database for document retrievals.

6. **Azure OpenAI**:
   - Provides the AI and machine learning backbone, analyzing queries and generating responses that are contextually aware and relevant to the user’s needs.

7. **InfluxDB (Time Series Data)**:
   - A database optimized for storing and retrieving time-series data from various equipment and sensors on the production line.

8. **Chroma Vector Database**:
   - Stores and manages access to manuals and troubleshooting guides which are used to answer queries related to equipment maintenance and other operational procedures.

9. **SLM/LLM Model “Phi-2”**:
   - A sophisticated language model that helps in interpreting complex technical queries and generating accurate responses based on the contextual understanding of the industry-specific data. For more information see [Phi-3 open models](https://azure.microsoft.com/en-us/products/phi-3)

10. **Assembly Line Simulator**:
    - Simulates data from the production line, which can be used for testing and demonstration purposes without the need to access the actual production environment.

11. **Azure IoT Operations and MQTT Broker**:
    - Manages device communication and data flow between the on-premises infrastructure and Azure services, ensuring secure and reliable data handling.

![Cerebral Architecture Diagram](/resources/images/architecture.png)

This modular yet integrated architecture allows Cerebral to offer a flexible, scalable solution adaptable to various industrial environments, enhancing operational efficiency through AI-driven automation and real-time data processing.

### Communication Flow

The decision tree for "Cerebral" illustrates the AI-driven process from user query to response generation, integrating both data retrieval and document look-up functionalities. Below is a breakdown of each step in the data flow:

- **User Prompt**:
  - The process begins when a user inputs a prompt, such as "Show me the oil temperature in the past 15 minutes." This prompt initiates the decision-making process within the system.

- **Query Classification Using Azure Open AI**:
  - The user's prompt is sent to Azure Open AI for query classification. Azure Open AI evaluates the content and context of the query to determine whether the user is requesting real-time data or looking for information contained in documents.

- **Classification**:
  - Based on Azure Open AI's analysis, the query is classified into one of two paths:
    - Data-related queries are directed towards executing database queries.
    - Document-related queries proceed towards searching within a vector database.

- **Execution Paths**:
  - **Data Path**:
    - **InfluxDB Query Execution**: If the query is classified as data-related, the user's prompt is converted into a specific query for InfluxDB, which retrieves time-series data relevant to the query.
    - **Data Interpretation and Analysis**: The retrieved data is then analyzed, and the system generates automated recommendations or insights based on the data.
  - **Document Path**:
    - **VectorDB Query Execution**: For document-related queries, the system translates the prompt into a search query for a chroma vector database. This database contains indexed manuals and troubleshooting guides.
    - **LLM Vector Search Integration**: The results from the vector database are integrated with the user's query to compile a comprehensive response detailing the information or steps required.

- **Backend Processing on the Edge**:
  - Queries are processed on backend systems located on the Edge, utilizing Azure IoT MQ for communication and executing necessary data queries or document retrievals.

- **Response Generation**:
  - **Dynamic HTML Response**: For both paths, the final step involves generating a dynamic HTML response that presents the information. For data queries, this may include graphs and tables displaying trends or specific data points. For document queries, this might consist of structured information or steps derived from the manuals.

- **Display to User**:
  - The generated response is displayed to the user, providing them with either the requested data visualized effectively or a well-structured answer from the document search, enabling them to make informed decisions or perform tasks more efficiently.

This communication flow highlights "Cerebral's" capability to handle diverse user requests by leveraging advanced AI classification and integration of multiple data sources, enhancing the decision-making and troubleshooting capabilities at Contoso Motors.

![Cerebral Data Flow](/resources/images/dataflow.png)

## Solution Overview

The solution is divided into two main components:
1. **Azure OpenAI Implementation:** This involves setting up Cerebral to leverage Azure OpenAI for natural language processing and query classification.
2. **RAG at the Edge:** This involves configuring Cerebral to use Chroma as a vector database and PHI-2 for on-premises language processing, allowing data processing to occur at the edge for faster response times.

## Pre-requisites

Before deploying Cerebral, several pre-requisites must be fulfilled to ensure a successful installation and operation. The system is designed to run on both virtual machines and physical servers that can handle edge computing tasks effectively.

### Hardware Requirements

1. **Linux-Based System**: Cerebral requires a Linux-based system, specifically a VM or physical machine running **Linux Ubuntu 22.04**. This system will perform as an edge server, handling queries directly from the production line and interfacing with other operational systems.

2. **Resource Specifications**:
   - **Minimal Resource Deployment**: For deployments using the Language Learning Model (LLM) hosted on Azure, a lighter resource footprint is feasible. A machine with at least **16 GB RAM and 4 CPU cores** should suffice.
   - **Full Resource Deployment**: For on-premises deployments where the System Lifecycle Management (SLM) is also located on-premises, a more robust system is required. It is recommended to use an Azure VM configured to simulate an edge environment with **32 GB RAM and 8 CPU cores**.

### Software Requirements

- **Azure CLI**: Essential for interacting with Azure services.
- **K3s**: Lightweight Kubernetes distribution suitable for edge computing environments.
- **Curl**: Tool to transfer data from or to a server, used during various installation steps.

### Network Requirements

To ensure smooth communication and operation of the Cerebral, specific network configurations are necessary. These configurations cater to the infrastructure's hybrid nature, leveraging both Azure services and on-premises components.

#### Azure Arc for Kubernetes

Cerebral utilizes [Azure Arc for Kubernetes](https://docs.microsoft.com/en-us/azure/azure-arc/kubernetes/overview) to extend Azure management capabilities to Kubernetes clusters anywhere. This integration allows for the management of Kubernetes clusters across on-premises, edge, and multi-cloud environments through Azure's control plane.

#### Control Plane

The control plane of Cerebral, managed through Azure Arc, requires network configurations that adhere to Azure Arc's [networking requirements](https://docs.microsoft.com/en-us/azure/azure-arc/kubernetes/network-requirements). It's crucial to ensure that all necessary ports and endpoints are accessible to facilitate command and control operations seamlessly.

#### Data Plane

For the data plane, which handles the direct processing and movement of operational data:
- **Port 443 (HTTPS)**: This port is used predominantly to secure data transmission across the network, ensuring encrypted communication for all data exchanges between the edge devices and the centralized data services.

### Note on Deployment Types

- **Cloud-Based LLM Deployment**: This setup requires minimal resources at the Edge and leverages Azure's robust cloud capabilities for processing and data handling, suitable for scenarios with adequate network connectivity and less stringent data locality requirements.
- **On-Premises SLM Deployment**: This approach is ideal for environments where the integration with on premises data is requiered and is requieres to have the SLM at the edge. It demands more substantial resources but provides enhanced control over data and processes.


## Solution Build Steps

### Step 1 - Building an Ubuntu VM running Azure IoT Operation

1. **Prepare Your Azure Arc-enabled Kubernetes Cluster on Ubuntu:**
   - Install `curl`:
     ```bash
     sudo apt install curl -y
     ```
   - Install Azure CLI:
     ```bash
     curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
     ```
   - Install Azure IoT Operations extension:
     ```bash
     az extension add --upgrade --name azure-iot-ops
     ```
   - Install K3S:
     ```bash
     curl -sfL https://get.k3s.io | sh –
     ```

2. **Set Up K3S Configuration:**
   - Create K3S configuration:
     ```bash
     mkdir ~/.kube
     sudo KUBECONFIG=~/.kube/config:/etc/rancher/k3s/k3s.yaml kubectl config view --flatten > ~/.kube/merged
     mv ~/.kube/merged ~/.kube/config
     chmod  0600 ~/.kube/config
     export KUBECONFIG=~/.kube/config
     kubectl config use-context default
     ```
   - Increase user watch/instance limits:
     ```bash
     echo fs.inotify.max_user_instances=8192 | sudo tee -a /etc/sysctl.conf
     echo fs.inotify.max_user_watches=524288 | sudo tee -a /etc/sysctl.conf
     sudo sysctl -p
     ```
   - Increase file descriptor limit:
     ```bash
     echo fs.file-max = 100000 | sudo tee -a /etc/sysctl.conf
     sudo sysctl -p
     ```

3. **Connect Your Cluster to Azure Arc:**
   - Login to Azure:
     ```bash
     az login
     ```
   - Set environment variables:
     ```bash
     export SUBSCRIPTION_ID=<YOUR_SUBSCRIPTION_ID>
     export LOCATION=<YOUR_REGION>
     export RESOURCE_GROUP=<YOUR_RESOURCE_GROUP>
     export CLUSTER_NAME=<YOUR_CLUSTER_NAME>
     export KV_NAME=<YOUR_KEY_VAULT_NAME>
     export INSTANCE_NAME=<YOUR_INSTANCE_NAME>
     ```
   - Set Azure subscription context:
     ```bash
     az account set -s $SUBSCRIPTION_ID
     ```
   - Register required resource providers:
     ```bash
     az provider register -n "Microsoft.ExtendedLocation"
     az provider register -n "Microsoft.Kubernetes"
     az provider register -n "Microsoft.KubernetesConfiguration"
     az provider register -n "Microsoft.IoTOperationsOrchestrator"
     az provider register -n "Microsoft.IoTOperations"
     az provider register -n "Microsoft.DeviceRegistry"
     ```
   - Create a resource group:
     ```bash
     az group create --location $LOCATION --resource-group $RESOURCE_GROUP --subscription $SUBSCRIPTION_ID
     ```
   - Connect Kubernetes cluster to Azure Arc:
     ```bash
     az connectedk8s connect -n $CLUSTER_NAME -l $LOCATION -g $RESOURCE_GROUP --subscription $SUBSCRIPTION_ID
     ```
   - Get `objectId` of Microsoft Entra ID application:
     ```bash
     export OBJECT_ID=$(az ad sp show --id bc313c14-388c-4e7d-a58e-70017303ee3b --query id -o tsv)
     ```
   - Enable custom location support:
     ```bash
     az connectedk8s enable-features -n $CLUSTER_NAME -g $RESOURCE_GROUP --custom-locations-oid $OBJECT_ID --features cluster-connect custom-locations
     ```
   - Verify cluster readiness for Azure IoT Operations:
     ```bash
     az iot ops verify-host
     ```
   - Create an Azure Key Vault:
     ```bash
     az keyvault create --enable-rbac-authorization false --name $KV_NAME --resource-group $RESOURCE_GROUP
     ```


### Step 2 - Install Cerebral

1. **Deploy Namespace, InfluxDB, Simulator, and Redis:**
   - Create a folder for Cerebral configuration files:
     ```bash
     mkdir cerebral
     cd cerebral
     ```
   - Apply the Cerebral namespace:
     ```bash
     kubectl apply -f https://raw.githubusercontent.com/armandoblanco/cerebral-app/main/deployment/cerebral-ns.yaml
     ```
   - Create a directory for persistent InfluxDB data:
     ```bash
     sudo mkdir /var/lib/influxdb2
     sudo chmod 777 /var/lib/influxdb2
     ```
   - Deploy InfluxDB:
     ```bash
     kubectl apply -f https://raw.githubusercontent.com/armandoblanco/cerebral-app/main/deployment/influxdb.yaml
     ```
   - Configure InfluxDB:
     ```bash
     kubectl apply -f https://raw.githubusercontent.com/armandoblanco/cerebral-app/main/deployment/influxdb-setup.yaml
     ```
   - Deploy the data simulator:
     ```bash
     kubectl apply -f https://raw.githubusercontent.com/armandoblanco/cerebral-app/main/deployment/cerebral-simulator.yaml
     ```
   - Validate the implementation:
     ```bash
     kubectl get all -n cerebral
     ```

2. **Access InfluxDB:**
   - Use a web browser to connect to the Server IP of the InfluxDB service to access its interface, example htttp://<IP Server>:8086. Validate that there is a bucket named `manufacturing` and that it contains a measurement called `assemblyline` with values. To access to Grafana the user is **admin** and the password id **ArcPassword123!!**

   ![Grafana](/resources/images/grafana.png)


3. **Install Redis:**
   - Deploy Redis to store user sessions and conversation history:
     ```bash
     kubectl apply -f https://raw.githubusercontent.com/armandoblanco/cerebral-app/main/deployment/redis.yaml
     ```

4. **Deploy Cerebral Application:**
   - Create an Azure OpenAI service in your subscription and obtain the key and endpoint for use in the application configuration.
   - Download the Cerebral application deployment file:
     ```bash
     wget https://raw.githubusercontent.com/armandoblanco/cerebral-app/main/deployment/cerebral.yaml
     ```
   - Edit the file with your Azure OpenAI instance details:
     ```bash
     nano cerebral.yaml
     ```
   - Apply the changes and deploy the application:
     ```bash
     kubectl apply -f cerebral.yaml
     ```

5. **Verify All Components:**
   - Ensure that all components are functioning correctly by checking the pods and services.


### Testing Cerebral

At this point in the setup, "Cerebral" is fully operational using only Azure Open AI for processing queries. Here are the steps to test the functionality of the system:

1. **Accessing the Web Interface**:
   - Open your web browser and navigate to the web address of your server appended with port 5000. For example, if you are running the server locally, you would go to:
     ```
     http://localhost:5000
     ```

     ![Login to Cerebral](/resources/images/login.png)

2. **Logging In**:
   - Once the Cerebral login page loads, use the following credentials to log in:
     - **Username**: agora
     - **Password**: ArcPassword123!!

3. **Using Cerebral**:
   - After logging in, you will be directed to the main interface where you can begin interacting with the system. You can start by typing a query related to the operational data or documentation in the provided text field.

   - **Interaction Tools**:
      - **Text Input Box**: Allows users to type in their questions or concerns.
      - **Verbose Mode Checkbox**: Users can toggle this to receive more detailed in the response generation and see the data flow.
      - **Send Button**: Sends the current query to the system for processing.
      - **Reset Chat History Button**: Clears the session history, allowing users to start afresh without previous interactions.

4. **Submitting Queries**:
   - Enter your question in the text box or choose a common question from the FAQ list displayed on the page. Hit the "Submit" button to see Cerebral in action.

   ![Login to Cerebral](/resources/images/cerebral-ask.png)

5. **Viewing Responses**:
   - The system will process your query using Azure Open AI, and the response, whether it be data visualizations or text information, will be displayed on the same page. This allows you to assess the accuracy and relevance of the response to your query.

    #### 1. User Query based in Data
    - **User Prompt**: "Show me the Oil temperature in the past 15 minutes."
      - The user, inputs a natural language query regarding oil temperature data over a specified time frame.

    ##### System Response
    - **Interpretation and Data Analysis**:
      - The system interprets the question and accesses real-time data from the "manufacturing" bucket via an InfluxDB query specifically tailored to retrieve oil temperature readings from the last 15 minutes.
      - The response includes a detailed analysis of the oil temperature trends observed, mentioning specific temperature readings at various intervals to give a comprehensive view of the data behavior.

    - **Proactive Recommendations**:
      - Based on the analyzed data, Cerebral offers proactive recommendations. It suggests initiating a quick system check to identify potential causes for the fluctuations observed in the oil temperatures, thereby aiding in preemptive maintenance and operational efficiency.

    - **Dynamic Graph of Oil Temperature**:
      - Below the textual analysis, a dynamic graph visually represents the oil temperature data over the specified period. This graphical representation allows users to easily visualize trends and anomalies in the data, enhancing the interpretative experience.

    ##### Interaction Features
    - The interface is designed for ease of use, allowing users to quickly navigate through historical queries and responses. The session maintains a continuous flow, making it easy for users to follow the conversation and refer back to earlier interactions.


   ![Response based in near real time data](/resources/images/query-data.png)


    #### 2. User Query based in Documents

    This screenshot illustrates the Cerebral SmartOps Assistant interface, where a user queries about troubleshooting a robotic arm motor. The system is designed to provide detailed, actionable advice based on documented resources, tailored to support manufacturing maintenance engineers.
    
      - **Prompt**: "How can we fix the problem with the motor of my robotic arm? Are there any guidelines or manuals?"
      - This prompt demonstrates the system's ability to understand and respond to detailed, technical queries. Users can input queries directly related to their field, with the system providing precise troubleshooting steps.

    - **System Response**:
      - **Detailed Guidance**: The response outlines essential steps for diagnosing the root cause of the problem, suggesting checks for motor wiring, encoders, and referring to the user manual for comprehensive troubleshooting procedures.
      - **Proactive Assistance**: It advises on inspecting for physical damage and provides guidance on how to access further technical support if necessary, embodying an all-encompassing support tool.

    - **Frequently Asked Questions (FAQ)**:
      - Quick-access buttons to common queries help streamline the troubleshooting process by providing immediate answers to standard questions, such as checking the oil temperature or evaluating assembly line performance.

    ##### Adaptability of the Interface

    - The user prompt can be tailored to fit different roles within the manufacturing environment. While the default setup caters to maintenance engineers, the underlying code can be modified to accommodate other technical roles, enhancing the system's versatility and application in diverse operational contexts.

    ##### Functionality
    - Cerebral integrates with Retrieval-augmented generation (RAG) for document retrieval, dynamically accessing operational manuals and troubleshooting guides. When fully deployed, it will use indexed information from the Chroma vector database and contextualize responses using SLM phi-2, allowing for highly tailored and informed interactions.

    ![Response based in near real time data](/resources/images/query-documents.png)

6. **Evaluating Performance**:
   - Test various queries to evaluate the performance and responsiveness of the system. Check how well the system interprets and responds to different types of queries, and note any areas for improvement.

By following these steps, you can ensure that "Cerebral" is functioning correctly and efficiently, leveraging Azure Open AI's capabilities to provide accurate and timely information to the end-user.


### Enabling Advanced Features with RAG at the Edge

Up to this point, Cerebral has been utilizing Azure Open AI to handle queries and provide responses. We are now advancing our capabilities by enabling Cerebral for use with Retrieval-augmented generation (RAG) on the Edge. This enhancement aims to leverage local resources more efficiently and provide faster, more contextually aware responses directly from the edge of the network.

#### Implementing Chroma (Vector DB) and SLM phi-2

- **Chroma (Vector DB)**: We will implement Chroma, a vector database that allows for efficient indexing and retrieval of documents and data. Chroma is designed to work seamlessly with AI models to provide rapid responses to queries by directly accessing relevant documents and data points.
  
- **SLM phi-2**: Alongside Chroma, the SLM phi-2 model will be utilized to provide an additional layer of context and depth to responses. This model enhances the AI's understanding of complex queries by incorporating advanced natural language processing capabilities.

#### Integration with Azure IoT Operations MQ

- **Azure IoT Operations MQ**: All communications within Cerebral will now leverage Azure IoT Operations MQ. This integration ensures that all data handling—from query processing to delivering responses—is managed effectively with minimal latency. It supports the robust, real-time processing needs of Cerebral, ensuring data is quickly relayed between the cloud and edge components.

#### Transition Impact

This strategic transition to RAG on the Edge marks a significant enhancement in how Cerebral processes information and interacts with users. By localizing critical processing tasks, we reduce dependency on central cloud resources, which minimizes delays and improves the system's overall efficiency. The implementation of Chroma and SLM phi-2 ensures that responses are not only fast but also contextually enriched, providing a more sophisticated level of interaction that is tailored to the specific needs of the operational environment.

#### Moving Forward

As we proceed with this transition, users can expect a more dynamic and responsive system capable of handling complex queries with greater precision and speed. This enhancement solidifies Cerebral's position as a cutting-edge tool in the realm of industrial operational technology, ready to tackle the challenges of modern manufacturing and production processes.

1. **Deploy Azure IoT Operations:**
  Read [this article for more information about Azure IoT Operations](https://learn.microsoft.com/en-us/azure/iot-operations/overview-iot-operations)

  **Importent.** Azure IoT Operations is only required up to the RAG at the Edge Implementation section, if you only want to test Cerebral using Azure Open AI you can skip the Azure IoT Operations implementation.

   - Verify cluster host configuration:
     ```bash
     az extension add --upgrade --name azure-iot-ops --version 0.5.1b1

     az iot ops verify-host
     ```
   - Deploy Azure IoT Operations:
     ```bash
     az iot ops init --subscription $SUBSCRIPTION_ID -g $RESOURCE_GROUP --cluster $CLUSTER_NAME --custom-location testscriptscluster-cl-4694 -n $INSTANCE_NAME --broker broker --kv-id /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KV_NAME --add-insecure-listener --simulate-plc
     ```

     **--add-insecure-listener** will turn off authentication the Azure IoT Operations MQ should only be used for testing purposes with a test cluster that's not accessible from the internet. Don't use in production. Exposing MQTT broker to the internet without authentication and TLS can lead to unauthorized access and even DDOS attacks.

2. **Deploy prerequisites:**

    - Install Helm 
      ```bash
      curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3

      chmod 700 get_helm.sh

      ./get_helm.sh

      helm version
      ```

    - Install Dapr runtime on the cluster, for more information see [here](https://learn.microsoft.com/en-us/azure/iot-operations/create-edge-apps/howto-develop-dapr-apps).
      ```bash
      helm repo add dapr https://dapr.github.io/helm-charts/
      helm repo update
      helm upgrade --install dapr dapr/dapr --version=1.11 --namespace dapr-system --create-namespace --wait
      ```

    - Deploy Azure IoT MQ - Dapr PubSub Component
      ```bash
      kubectl apply -f https://raw.githubusercontent.com/armandoblanco/cerebral-app/main/deployment/rag-on-the-edge/rag-mq-components.yaml
      ```

2. **Deploy RAG on the Edge:**
    - Deploy tho other components of RAG on the Edge
      ```bash
      kubectl apply -f https://raw.githubusercontent.com/armandoblanco/cerebral-app/main/deployment/rag-on-the-edge/rag-vdb-dapr-workload.yaml
      kubectl apply -f https://raw.githubusercontent.com/armandoblanco/cerebral-app/main/deployment/rag-on-the-edge/rag-interface-dapr-workload.yaml
      kubectl apply -f https://raw.githubusercontent.com/armandoblanco/cerebral-app/main/deployment/rag-on-the-edge/rag-web-workload.yaml
      kubectl apply -f https://raw.githubusercontent.com/armandoblanco/cerebral-app/main/deployment/rag-on-the-edge/rag-llm-dapr-workload.yaml
      ```


### Conclusion

By following these steps, you should have a fully functioning Cerebral implementation integrated with Azure IoT Operations and ready for real-time data analysis and troubleshooting. This setup supports both Azure OpenAI and on-premises RAG processing, offering flexibility and high performance in diverse operational environments.