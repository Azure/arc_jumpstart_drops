import openai
from openai import AzureOpenAI
from dotenv import load_dotenv
import os

load_dotenv()  # Load environment variables from .env file
MODEL_NAME = os.getenv("CHATGPT_MODEL")

client = AzureOpenAI(
  azure_endpoint = os.getenv("AZURE_OPENAI_ENDPOINT"), 
  api_key=os.getenv("AZURE_OPENAI_API_KEY"),  
  api_version="2024-03-01-preview"
)

def classify_text(question):
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

# Test the function
print(classify_text("What are the current metrics for our main system?"))
print(classify_text("I have a problem with my turbine, how can I fix it?"))

