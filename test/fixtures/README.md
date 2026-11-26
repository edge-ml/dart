# Test fixtures

`torch_cnn/` is a small TorchCNN1D model (raw time-series, Z normalizer) exported
by the edge-ml ml service, with reference outputs from the eager PyTorch module:

- `model.pte`, `manifest.json`: the ExecuTorch export, as served by
  `GET /ml/device/{key}/models/{id}/executorch/...`
- `expected.json`: input windows and the logits PyTorch computes for them

Regenerate with the ml service's environment (e.g. its Docker image), from the
ml repo root:

```sh
python /path/to/edge-ml-dart/tool/make_fixture.py /path/to/edge-ml-dart/test/fixtures/torch_cnn
```

`audio_mixed/` and `audio_only/` are models that take sound (manifest schema
2, ExecuTorch manifest), made by the edge-ml JavaScript library's
`__tests__/fixtures/make_audio_fixtures.py` from the backend's audio
pipeline: 500 ms windows, sound at 8 kHz, plus acc_x/acc_y at 50 Hz for the
mixed one. `reference.json` has the Python scores, the windows (sound as
base64 float32) and the same sound at 48 kHz per window.

`resampler_vector.json` is the JavaScript library's `Resampler` output for a
44.1 kHz chirp; the Dart port must reproduce it.
