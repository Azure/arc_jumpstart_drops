from openai import AzureOpenAI
from dotenv import load_dotenv
import os

load_dotenv()  # Load environment variables from .env file

print(os.getenv("AZURE_OPENAI_ENDPOINT"))
print(os.getenv("AZURE_OPENAI_API_KEY"))

MODEL_NAME = os.getenv("CHATGPT_MODEL")
print(MODEL_NAME)

client = AzureOpenAI(
  azure_endpoint = os.getenv("AZURE_OPENAI_ENDPOINT"), 
  api_key=os.getenv("AZURE_OPENAI_API_KEY"),  
  api_version="2024-03-01-preview"
)

conversation=[
    {"role": "system", "content": "Assistant is an intelligent chatbot designed to help users answer technical questions about Azure OpenAI Serivce. Only answer questions using the context below and if you're not sure of an answer, you can say 'I don't know'."},
    {"role": "user", "content": "What is Azure OpenAI Service?"}
]

def classify_question(question):
    categories = ["data", "documentation", "general"]
    
    prompt_text = f"For the below text, provide one single label each from the following categories:\n- Category: {', '.join(categories)}\n\nThe system should analyze the question and identify if it is related to data that could exist and get in a time series database in InfluxDB (e.g., statistics, metrics, performance, quality, telemetry, current variable values, etc.). If so, the system should respond with 'data'. If the question is related to manuals, troubleshooting, or how to solve a problem based on documents, it should respond with 'documentation'. For all other questions, the system should respond with 'general'. Examples: Question: What are the current metrics for our main system? Category: data Question: How can I troubleshoot the connection issue? Category: documentation\n\nQuestion: {question}\nCategory:"

    response = client.completions.create(
        model="gpt-35-turbo",
        prompt=prompt_text,
        temperature=0,
        max_tokens=60,
        top_p=1,
        frequency_penalty=0,
        presence_penalty=0,
        stop=["\n"]
    )

    return response.choices[0].text.strip()

def chat_with_openai_for_data(question, client, conversation):

    conversation.append({"role": "user", "content": question})

    response = client.chat.completions.create(
            model=MODEL_NAME,
            messages=conversation
        )
    #print(response.choices[0].message.content)
    conversation.append({"role": "system", "content": response.choices[0].message.content})

    #print(response)
    #print(response.model_dump_json(indent=2))
    print(response.choices[0].message.content)

    conversation.append({"role": "user", "content": question})
    response = client.chat.completions.create(
        model=os.getenv("CHATGPT_MODEL"),
        messages=conversation
    )
    conversation.append({"role": "system", "content": response.choices[0].message.content})
    return response.choices[0].message.content

def chat_with_local_llm(question):
    #local_model = pipeline("text-generation", model="gpt2")  # Ajustar según la disponibilidad del modelo
    #response = local_model(question, max_length=50)
    return ""

def main():
    while True:
        user_input = input("User: ")
        conversation = conversation.append({"role": "user", "content": user_input})
        
        category = classify_question(user_input)
        print(category)

        if category == "data":
            print("Chatting with OpenAI for data-related question...")
            response = chat_with_openai_for_data(user_input, client, conversation)
            print(response)

        else:
            print("Using local LLM for non-data question...")
            response = chat_with_local_llm(user_input)
        

if __name__ == "__main__":
    main()