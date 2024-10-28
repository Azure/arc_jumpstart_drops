#!/usr/bin/python
import socket
import paho.mqtt.client as paho
import random
import json
from datetime import datetime

# MQTT Configuration
broker = "localhost"
publishing_port = 1883
topic = "LoRaWANGateway/Data"
json_topic = "loradf"

# UDP Server Configuration
HOST = "0.0.0.0"  # Standard loopback interface address (localhost)
PORT = 1700  # Port to listen on (non-privileged ports are > 1023)

# Simulation Configuration
gateway_ids = ["gateway_000A", "gateway_000B", "gateway_000C"]  # Example gateway IDs

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

def generate_simulated_data():
    """Generate realistic simulated values for LoRa metrics"""
    return {
        "timestamp": datetime.now().isoformat(),
        "gateway_id": random.choice(gateway_ids),
        "rssi": random.randint(-120, -40),  # Typical LoRa RSSI range
        "snr": round(random.uniform(-20, 10), 1)  # Typical LoRa SNR range
    }

def format_json_payload(data):
    try:
        # Get simulated values
        simulated_data = generate_simulated_data()
        
        # Create the JSON payload
        payload = {
            "raw_data": data.hex(),
            "timestamp": simulated_data["timestamp"],
            "gateway_id": simulated_data["gateway_id"],
            "rssi": simulated_data["rssi"],
            "snr": simulated_data["snr"]
        }
        
        return json.dumps(payload)
    except Exception as e:
        print(f"Error formatting JSON: {e}")
        return None

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
                
                # Publish to original topic
                client.publish(topic, data)
                
                # Format and publish JSON data
                json_payload = format_json_payload(data)
                if json_payload:
                    client.publish(json_topic, json_payload)
                    print(f"Published JSON payload: {json_payload}")
                
            except Exception as e:
                print(f"Error: {e}")

if __name__ == "__main__":
    main()