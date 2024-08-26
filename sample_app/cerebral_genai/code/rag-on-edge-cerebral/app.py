from flask import Flask, render_template, request, redirect, url_for, session, jsonify, render_template_string
#import openai
from openai import AzureOpenAI
from dotenv import load_dotenv
import os
from influxdb_client import InfluxDBClient
from influxdb_client.client.query_api import QueryOptions
import plotly.express as px
#from io import BytesIO
import base64
import pandas as pd
from flask_session import Session
import redis

#import pytz

app = Flask(__name__)
app.secret_key = 'una_clave_secreta_muy_dificil_de_adivinar' 

#load_dotenv()  # Load environment variables from .env file

AZURE_OPENAI_API_KEY=os.getenv("AZURE_OPENAI_API_KEY")
CHATGPT_MODEL=os.getenv("CHATGPT_MODEL")
AZURE_OPENAI_ENDPOINT=os.getenv("AZURE_OPENAI_ENDPOINT")
OPENAI_API_VERSION=os.getenv("OPENAI_API_VERSION")
INFLUXDB_URL=os.getenv("INFLUXDB_URL")
INFLUXDB_BUCKET=os.getenv("INFLUXDB_BUCKET")
INFLUXDB_TOKEN=os.getenv("INFLUXDB_TOKEN")
INFLUXDB_ORG=os.getenv("INFLUXDB_ORG")
REDIS_URL=os.getenv("REDIS_URL")

# Configure session to use Redis
app.config['SESSION_TYPE'] = 'redis'
app.config['SESSION_PERMANENT'] = False  # You can set this to True if you want
app.config['SESSION_USE_SIGNER'] = True  # If you want to sign the cookie
app.config['SESSION_REDIS'] = redis.from_url(REDIS_URL)

Session(app)

MODEL_NAME = CHATGPT_MODEL

#Classify question
client = AzureOpenAI(
  azure_endpoint = AZURE_OPENAI_ENDPOINT, 
  api_key=AZURE_OPENAI_API_KEY,  
  api_version=OPENAI_API_VERSION
)

#Generate InfliuxDB query
client2 = AzureOpenAI(
  azure_endpoint = AZURE_OPENAI_ENDPOINT, 
  api_key=AZURE_OPENAI_API_KEY,  
  api_version=OPENAI_API_VERSION
)

#Generate recommendations
clientRecommendations = AzureOpenAI(
  azure_endpoint = AZURE_OPENAI_ENDPOINT, 
  api_key=AZURE_OPENAI_API_KEY,  
  api_version=OPENAI_API_VERSION
)

#INFLUXDB_URL=INFLUXDB_URL
#INFLUXDB_BUCKET=INFLUXDB_BUCKET
#INFLUXDB_TOKEN=INFLUXDB_TOKEN
#INFLUXDB_ORG=INFLUXDB_ORG

clientInfluxDb = InfluxDBClient(url=INFLUXDB_URL, token=INFLUXDB_TOKEN, org=INFLUXDB_ORG)

conversation =""

conversation=[
    {
        "role": "system",
        "content": "Assistant is an expert technical support chatbot specialized in the manufacturing sector, particularly skilled in maintenance, support, and operation of automotive assembly lines. It should answer all questions with this expertise in mind. If the assistant is unsure of an answer, it can say 'I don't know'."
    },
    {
        "role": "user",
        "content": "I am having problems with my Kuka roboric arm for car hybrid assembly line, how can I reset the system?"
    }
]

def execute_query_and_return_data(url, token, org, bucket, query):
    client = InfluxDBClient(url=url, token=token, org=org)
    query_api = client.query_api(query_options=QueryOptions(profilers=["query", "operator"]))
    #result = query_api.query(query=query)
    result = query_api.query(query=query)
    print("Query executed successfully")
 
    try:
        
        points = [point for table in result for point in table.records]
        if len(points) == 1:
            single_point = points[0]
            print("Aggregation result:", single_point.get_value())
            return single_point.get_value()
        else:
            # Múltiples puntos, manejo como serie de tiempo
            #for point in points:
            #    print(f'Time: {point.get_time()}, Value: {point.get_value()}')
            data = []
            for table in result:
                try:
                    for record in table.records:
                        data.append({
                            '_time': record.get_time(),
                            '_field': record.get_field(),
                            '_value': record.get_value()
                        })
                except Exception as e:
                    print(f"Error processing record: {e}")
                    continue  # Skip to the next record
    except Exception as e:
        print(f"Failed to execute query: {e}")
        data = result
    finally:
        client.close()

    return data

    #data = []
    #for table in result:
    #    for record in table.records:
    #        data.append({
    #            '_time': record.get_time(),
    #            '_field': record.get_field(),
    #            '_value': record.get_value()
    #        })
    #client.close()
    #return data

def clean_string(original_string):
    return original_string.replace("Output: ", "", 1)


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

def generate_recommendations(question, response, result):

    conversation=[
        {
            "role": "system",
            "content": """
            I am an agent specialized in technical support for automobile manufacturing, particularly skilled in the maintenance, support, and operation of automotive assembly lines. My role is to interpret user questions with expertise, analyze production data, and provide proactive recommendations to optimize assembly line operations. Give me the Interpretation and response, including data analysis and proactive recommendations separeted in different paragraphs. Instructions:
            1. Avoid technological terms and explanations that the solution was built with such as InfluxDb, bucket, etc, keep it like an automotive manufacturing plant manager.
            2. Format should be <h3>Interpretation:</h3>Generated text <h3>Data Analysis:</h3>Generated text <h3>Proactive Recommendations:</h3>Generated text<BR></BR>."""
            
        }
    ]

    conversation.append({"role": "user", "content": f"question: {question} and data received: {result} and row data {response}"})

    response = clientRecommendations.chat.completions.create(
            model=MODEL_NAME,
            messages=conversation
        )
    
    conversation.append({"role": "system", "content": response.choices[0].message.content})
    print(response.choices[0].message.content)

    return response.choices[0].message.content

def chat_with_openai_for_data(question):
    print("chat_with_openai_for_data")

    conversation=[
        {
            "role": "system",
            "content": f"""
            User submits a query regarding the manufacturing process. Generate an InfluxDB query for data from the '{INFLUXDB_BUCKET}' bucket using the specified fields:
            - plant, country, assembly_line, car_id, model, color, engine_type, assembly_status, shift, Drive1_Voltage, Cooler_ON, Fan001_On, Heater_ON, Pump1_Temperature_Flow, Pump2_Temperature_Flow, Pump3_Temperature_Flow, Pumps_Total_Flow, Pressure_Filter_Inlet, Pressure_Filter_Outlet, RobotPosition_J0, RobotPosition_J1, RobotPosition_J2, RobotPosition_J3, RobotPosition_J4, RobotPosition_J5, Tank_Level, Drive1_Current, Drive1_Frequency, Drive1_Speed, Drive2_Current, Drive2_Frequency, Drive2_Speed, Drive2_Voltage, Current, Voltage, Temperature, Humidity, VacuumAlert, VacuumPressure, Oiltemperature, OiltemperatureTarget, Waste, WasteReason, LostTime, LostTimeReason, LostTimeTimeCount, ScheduledBatteries, CompletedBatteries, ScheduledBatteriesPerHour, ImpactTest, VibrationTest, CellTest, DownTime, Thruput, OverallEfficiency, Availability, Performance, Quality, PlannedProductionTime, ActualRuntime, UnplannedDowntime, PlannedDowntime, PlannedQuantity, ActualQuantity, RejectedQuantity, OEE_GoalbyPlant, OEE_Mexico, OEE_BatteryA, OEE_BatteryB, OEE_BatteryC

            Instructions:

            1. Determine if the query seeks the latest data point or spans a specific time period. Default to data from the last hour if unspecified.
            2. Construct an InfluxDB query specific to the '{INFLUXDB_BUCKET}' bucket that includes ["_measurement"] == "assemblyline" and identifies the relevant _field for the query.
            3. If the query relates to real-time production line telemetry, Advaris, ODEN, QAD, or Quality cost, create the query. Otherwise, indicate "No data available."
            4. Provide the complete InfluxDB query or a statement on data availability.
            5. Just give me the query.
            6. Remove additional text such as comments # or " or ''' or ''' or ```
            Example Outputs:

            Query: "What is the latest Drive1 Speed at the Monterrey plant?"
            Output: from(bucket: "{INFLUXDB_BUCKET}") |> range(start: -1m) |> filter(fn: (r) => r["_measurement"] == "assemblyline") |> filter(fn: (r) => r["_field"] == "Drive1_Speed") |> last())
            Query: "Assembly statuses over the past two days?"
            Output: from(bucket: "{INFLUXDB_BUCKET}") |> range(start: -48h) |> filter(fn: (r) => r["_measurement"] == "assemblyline") |> filter(fn: (r) => r["_field"] == "assembly_status")
            Query: "What is the staff's favorite lunch?"
            Output: "No data available."
            """
        }
    ]

    conversation.append({"role": "user", "content": question})

    response = client2.chat.completions.create(
            model=MODEL_NAME,
            messages=conversation
        )
    
    conversation.append({"role": "system", "content": response.choices[0].message.content})
    print(response.choices[0].message.content)

    clean_response = clean_string(response.choices[0].message.content)

    #return response.choices[0].message.content
    return clean_response

def clean_string(original_string):
    clean_string = original_string.replace("```", "")
    clean_string = clean_string.replace("Output:", "")
    clean_string = clean_string.replace("Query:", "")
    return clean_string

def chat_with_local_llm(question):
    conversation.append({"role": "user", "content": question})

    response = client.chat.completions.create(
            model=MODEL_NAME,
            messages=conversation
        )
    #print(response.choices[0].message.content)
    conversation.append({"role": "system", "content": response.choices[0].message.content})

    #print(response)
    return response.choices[0].message.content

#def fetch_graph_data(data):
#    print("fetch_graph_data")
#    raw_data = data
#    times = [data['_time'].strftime("%Y-%m-%d %H:%M:%S") for data in raw_data]
#    values = [data['_value'] for data in raw_data]
#    return times, values

def generate_html_table(data):
    
    html=""
    print("generate_html_table")
    print(data)
    if isinstance(data, float):
        return f"<B>Value is: </B> {str(data)}"
    elif isinstance(data, str):
        return f"<b>Value is: </b> {data}"
    else:
        html = '<table border="1">'
        html += '<tr><th>Time</th><th>Field</th><th>Value</th></tr>' 

        try:

            for entry in data:
                time_str = entry['_time'].strftime('%Y-%m-%d %H:%M:%S %Z') 
                field = entry['_field']
                value = entry['_value']
                html += f'<tr><td>{time_str}</td><td>{field}</td><td>{value}</td></tr>'
            html += '</table>'
        except Exception as e:
            print(f"Error generating table: {e}")

    return html

def generate_html_image(raw_data):
    print("generate_html_image")
    html =""
    try:
        data = pd.DataFrame(raw_data)
        data['_time'] = pd.to_datetime(data['_time']).dt.strftime('%Y-%m-%d %H:%M:%S %Z')
        data.rename(columns={'_field': 'Field', '_value': 'Value'}, inplace=True)
        
        # Generate the plot
        fig = px.line(data, x='_time', y='Value', title='Time Series Data', labels={'_time': 'Time', 'Value': data['Field'][0]})
        
        # Convert the figure to a PNG image byte stream
        img_bytes = fig.to_image(format="png")
        encoded = base64.b64encode(img_bytes).decode('utf-8')  # Encode the bytes to base64 and decode to a string

        # Embed the image in HTML
        html = f'''
        <br></br><b>Dynamic Graph of {data['Field'][0]}</b><br></br>
        <img src="data:image/png;base64,{encoded}">
        '''
    except Exception as e:
        print(f"Error generating image: {e}")
        html = "No image was generated."
    return html

@app.route('/', methods=['GET', 'POST'])
def home():
    if 'username' in session:
        return render_template('index.html')
    return redirect(url_for('login'))
    

@app.route('/handle_button_click', methods=['POST'])
def handle_button_click():
    button_id = request.form['button_id']
    recommendation = ""
    question = ""
    plot_html = ""
    response = ""
    influxquery=""

    if button_id == "btnSend":
        #question = request.form['txtQuestion']
        question = request.form.get('txtQuestion', '')
    elif button_id == "btnFAQ1":
        question = "What is the last color manufactured?"
    elif button_id == "btnFAQ2":    
        question = "Show me the Oil temperature in the past 15 minutes?"
    elif button_id == "btnFAQ3": 
        question = "What are the steps to maintain and change the oil in my kuka robotic arm?"
    elif button_id == "btnFAQ4": 
        question = "How can we fix the problem with the motor of my robotic arm? Are there any guidelines or manuals?"
    elif button_id == "btnFAQ5": 
        question = "What is the current performance of the assembly line?"
    elif button_id == "btnFAQ6": 
        question = "Estoy teniendo problemas con mi cinta transportadora FHM, como puedo reemplazar los tornillos y asegurar que no esten flojos"
    else:
        question = "No question was found."

    user_input = question
    category = classify_question(user_input)
    
    verbose_mode = request.form.get('chkVerbose') == 'true' 
    print(verbose_mode)

    if 'history' not in session:
        session['history'] = []
        
    if category == "data":
        influxquery = chat_with_openai_for_data(user_input)
        result_data_influx = execute_query_and_return_data(INFLUXDB_URL, INFLUXDB_TOKEN, INFLUXDB_ORG, INFLUXDB_BUCKET, clean_string(influxquery))
        recommendation = generate_recommendations(user_input, influxquery, result_data_influx)
        table_html = generate_html_table(result_data_influx)
        plot_html = generate_html_image(result_data_influx)

        response = f"{ table_html }"  

    elif category == "documentation":
        print("Documentation")
        response = chat_with_local_llm(user_input) 
        print(f"Response: {response}") 
        recommendation = response
    else:
        recommendation = "No appropriate category was found to answer this question."
    
    svg_server = "<svg width='38' height='38'><image href='/static/images/openai.png' height='38' width='38' /></svg>"
    svg_client = "<svg width='38' height='38'><image href='/static/images/user.jpeg' height='38' width='38' /></svg>"
    
    if verbose_mode:
        answer = f"<h2>Step 1 - Classification:</h2> {category}  <h2>Step 2 - Query:</h2> {clean_string(influxquery)} <h2>Step 3 - Raw Data: </h2>{response}  <h2>Step 4 - Interpretation:</h2> {recommendation} <h2>Step 4 - Graph:</h2> {plot_html} " 
    else:
        answer = f"<BR/> {recommendation} <BR/> {plot_html} <BR/>"

    session['history'].append(f"<span class='question'><B>{svg_client} Armando Blanco - Question: {user_input} </B></span><span class='answer'> {svg_server} Cerebral - Answer {answer}</span>")
    session['last_response'] = f"{category}  -- {clean_string(influxquery)}"
    updated_history = session.get('history', [])
    #last_response = f"{category}  -- {clean_string(influxquery)}"
    last_response = ""
    session['history'] = updated_history
    session['last_response'] = last_response
    return jsonify(history=updated_history, last_response=last_response)


@app.route('/reset', methods=['POST'])
def reset():
    session.pop('history', None)  # Clear chat history
    return redirect(url_for('home'))

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        username = request.form['username']
        password = request.form['password']
        # Here you should properly validate the credentials
        if username == 'agora' and password == 'ArcPassword123!!':  # Basic example
            session['username'] = username
            return redirect(url_for('home'))
        else:
            return 'Invalid username or password'
    return render_template('login.html')

@app.route('/logout')
def logout():
    session.pop('username', None)
    return redirect(url_for('login'))



if __name__ == '__main__':
    #app.run(debug=True)
    app.run(debug=True, host='0.0.0.0', port=5000)
