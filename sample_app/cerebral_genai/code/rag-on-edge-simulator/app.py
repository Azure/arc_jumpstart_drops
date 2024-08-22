from influxdb_client import InfluxDBClient, Point, WritePrecision
from influxdb_client.client.write_api import SYNCHRONOUS
from influxdb_client.client.query_api import QueryOptions
import random
import json
import time
from datetime import datetime
import os

# InfluxDB Settings
INFLUXDB_URL = os.getenv("INFLUXDB_URL")
INFLUXDB_TOKEN = os.getenv("INFLUXDB_TOKEN")
INFLUXDB_ORG = os.getenv("INFLUXDB_ORG")
INFLUXDB_BUCKET = os.getenv("INFLUXDB_BUCKET")
VERBOSE = bool(os.getenv("VERBOSE", "False"))

# Connect to InfluxDB
client = InfluxDBClient(url=INFLUXDB_URL, token=INFLUXDB_TOKEN, org=INFLUXDB_ORG)
write_api = client.write_api(write_options=SYNCHRONOUS)
query_api = client.query_api()

def generate_data():
    models = ["SUV", "Sedan", "Coupe"]
    colors = ["red", "blue", "black"]
    engine_types = ["electric", "hybrid", "gasoline"]
    assembly_statuses = ["InProgress", "Downtime"]
    shifts = ["morning", "afternoon", "night"]
    waste_reasons = ["defect", "rework", "spoilage"]
    lost_time_reasons = ["maintenance", "operator", "material"]

    data = {
        "plant": "Monterrey",
        "country": "Mexico",
        "assembly_line": "E-001",
        "car_id": "E-001",
        "model": random.choice(models),
        "color": random.choice(colors),
        "engine_type": random.choice(engine_types),
        "assembly_status": random.choice(assembly_statuses),
        "shift": random.choice(shifts),
        "Drive1_Voltage": random.uniform(190, 200),
        "Cooler_ON": random.choice([True, False]),
        "Fan001_On": random.choice([True, False]),
        "Heater_ON": random.choice([True, False]),
        "Pump1_Temperature_Flow": random.uniform(20, 30),
        "Pump2_Temperature_Flow": random.uniform(20, 30),
        "Pump3_Temperature_Flow": random.uniform(20, 30),
        "Pumps_Total_Flow": random.uniform(30, 35),
        "Pressure_Filter_Inlet": random.uniform(1, 2),
        "Pressure_Filter_Outlet": random.uniform(0.5, 1.5),
        "RobotPosition_J0": random.uniform(0, 5),
        "RobotPosition_J1": random.uniform(0, 5),
        "RobotPosition_J2": random.uniform(0, 5),
        "RobotPosition_J3": random.uniform(0, 5),
        "RobotPosition_J4": random.uniform(0, 5),
        "RobotPosition_J5": random.uniform(0, 5),
        "Tank_Level": random.uniform(60, 70),
        "Drive1_Current": random.uniform(0.4, 0.6),
        "Drive1_Frequency": 30,
        "Drive1_Speed": 30,
        "Drive1_Voltage": random.uniform(190, 200),
        "Drive2_Current": random.uniform(0.4, 0.6),
        "Drive2_Frequency": 30,
        "Drive2_Speed": 30,
        "Drive2_Voltage": random.uniform(190, 200),
        "Current": random.uniform(0, 0.01),
        "Voltage": random.uniform(100, 110),
        "Temperature": random.uniform(70, 80),
        "Humidity": random.uniform(40, 50),
        "VacuumAlert": random.choice([True, False]),
        "VacuumPressure": random.uniform(10, 20),
        "Oiltemperature": random.uniform(350, 390),
        "OiltemperatureTarget": 375,
        "Waste": random.uniform(1, 2),
        "WasteReason": random.choice(waste_reasons),
        "LostTime": "SPT",
        "LostTimeReason": random.choice(lost_time_reasons),
        "LostTimeTimeCount": random.randint(90, 100),
        "ScheduledBatteries": random.randint(8, 12),
        "CompletedBatteries": random.randint(3, 7),
        "ScheduledBatteriesPerHour": random.randint(280, 320),
        "Temperature": random.uniform(230, 240),
        "ImpactTest": random.uniform(780, 790),
        "VibrationTest": random.uniform(6, 7),
        "CellTest": random.uniform(400, 410),
        "DownTime": random.randint(2, 6),
        "Thruput": random.randint(28, 32),
        "OverallEfficiency": random.randint(88, 92),
        "Availability": random.randint(93, 97),
        "Performance": random.randint(93, 97),
        "Quality": random.randint(93, 97),
        "PlannedProductionTime": random.randint(58, 62),
        "ActualRuntime": random.randint(960, 965),
        "UnplannedDowntime": random.randint(295, 300),
        "PlannedDowntime": 0,
        "PlannedQuantity": random.randint(290, 310),
        "ActualQuantity": random.randint(280, 290),
        "RejectedQuantity": random.randint(10, 20),
        "OEE_GoalbyPlant": random.uniform(78, 82),
        "OEE_Mexico": random.uniform(95, 96),
        "OEE_BatteryA": random.uniform(96, 97),
        "OEE_BatteryB": random.uniform(94, 95),
        "OEE_BatteryC": random.uniform(95, 96)
    }
    
    return data

def write_data_to_influxdb(measurement_name, timestamp):
    
        data = generate_data()
        #point = Point("factory").tag("plant", "Monterrey").tag("country", "Mexico").tag("assembly_line", "E-001").field("car_id", "E-001")
        point = Point(measurement_name).time(timestamp, WritePrecision.NS)
        
        for key, value in data.items():
            point.field(key, value)

        write_api.write(bucket=INFLUXDB_BUCKET, record=point)
        if VERBOSE:
            print(f"Written data to InfluxDB: {data}")


if __name__ == "__main__":
    while True:
        write_data_to_influxdb("assemblyline", datetime.utcnow().isoformat())
        time.sleep(60) 

