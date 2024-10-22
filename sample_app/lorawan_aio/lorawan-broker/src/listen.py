#!/usr/bin/python
import socket
import paho.mqtt.client as paho
import random

# MQTT Configuration
broker = "localhost"
publishing_port = 1883
topic = "LoRaWANGateway/Data"

# UDP Server Configuration
HOST = "0.0.0.0"  # Standard loopback interface address (localhost)
PORT = 1700  # Port to listen on (non-privileged ports are > 1023)

def on_publish(client, userdata, result):
    print("Data published")
    print(result)

def create_mqtt_client():
    client_id = f'python-mqtt-{random.randint(0, 1000)}'
    
    # Check if CallbackAPIVersion is available (newer paho-mqtt versions)
    if hasattr(paho, 'CallbackAPIVersion'):
        client = paho.Client(paho.CallbackAPIVersion.VERSION1, client_id)
    else:
        # For older paho-mqtt versions
        client = paho.Client(client_id)
    
    client.on_publish = on_publish
    return client

def main():
    # Set up MQTT client
    client = create_mqtt_client()
    client.connect(broker, publishing_port)

    # Set up UDP server
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind((HOST, PORT))
        print(f"Waiting for UDP packets on port {PORT}")

        while True:
            try:
                data, addr = s.recvfrom(1024)
                print(f"Received packet from {addr}")
                client.publish(topic, data)
            except Exception as e:
                print(f"Error: {e}")

if __name__ == "__main__":
    main()