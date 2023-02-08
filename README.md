# Edge app Shelly Integration

This is an app that adds possibility to use Shelly devices connected to an edge
client.

This app is not complete and at the moment there are only a few devices working.

| Device name | Model name |
|-------------|------------|
| Plug-S      | `SHPLG-S`  |
| Motion      | `SHMOS-01` |

## Configuration of Shelly device

The app uses the edge-clients build in MQTT broker for connections with the
Shelly devices. These devices need to connect to the Edge Client MQTT broker on
port 1883 (unsecured). The MQTT settings need to be done in the Web interface
for the device by adding the IP or hostname of the broker. Make sure that the
broker is running and listening on the same network range as the edge client.

When Shelly devices connect to the broker they "announce" their presence. This
message is used to add the device and functions as needed. If the Shelly device
is restarted the app will once again check that all functions are created
correctly.