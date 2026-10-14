# edge_ml_dart example

Records the phone's accelerometer and gyroscope into an edge-ml dataset (tap a
label while recording to label from that moment on), trains a model from a
preset, and classifies live sensor data on the device.

```sh
flutter run                               # Android / iOS

dart run executorch_flutter:setup_web     # once, for the web
flutter run -d chrome
```

Enter your edge-ml URL and the project's Device API write key on the first
screen.
