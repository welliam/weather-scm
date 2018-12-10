#!/usr/bin/python
import Adafruit_DHT
PIN = 14
humidity, temperature = Adafruit_DHT.read_retry(Adafruit_DHT.DHT11, PIN)
print('--temperature {} --humidity {}'.format(
    int(temperature * 9/5 + 32),
    int(humidity),
))
