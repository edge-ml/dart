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
