#!/usr/bin/python
import socket, time
import paho.mqtt.client as paho
import random

broker="localhost"
publishingport=1883
def on_publish(client,userdata,result):             #create function for callback
    print("data published")
    print(result)
    pass

client_id = f'python-mqtt-{random.randint(0, 1000)}'
client1= paho.Client(paho.CallbackAPIVersion.VERSION1, client_id)                           #create client object
client1.on_publish = on_publish                          #assign function to callback
client1.connect(broker,publishingport)                                 #establish connection

HOST = "0.0.0.0"  # Standard loopback interface address (localhost)
PORT = 1700  # Port to listen on (non-privileged ports are > 1023)

st = socket.socket(socket.AF_INET, socket.SOCK_DGRAM | socket.SO_REUSEADDR)
st.bind((HOST, PORT))

print("waiting on port", PORT)
while 1:
    data, addr = st.recvfrom(1024)
    ret= client1.publish("LoRaWANGateway/Data", data) 

