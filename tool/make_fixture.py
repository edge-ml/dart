"""Exports a tiny trained model as model.pte + manifest.json + expected.json
(an input window and the logits the eager PyTorch pipeline produces for it).
Run inside the ml image, from the ml repo root:  python make_fixture.py <out_dir>"""
import json
import os
import sys

import numpy as np
import torch

sys.path.insert(0, "tests")
from test_torch_executorch import make_model_doc, make_windower, make_windows, train_pipeline  # noqa: E402
from app.ml.Pipelines.Categories.FeatureExtraction.RawSensorExtractor import RawSensorExtractor  # noqa: E402
from app.ml.Pipelines.Categories.Normalizer.ZNormalizer import ZNormalizer  # noqa: E402
from app.ml.Pipelines.Categories.Classifier.TorchCNN1D import TorchCNN1D  # noqa: E402
from app.ml.PipelineExport.Executorch.ExecutorchCompiler import (  # noqa: E402
    buildExecutorchManifest, buildExecutorchPte, buildExportModule,
)

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
torch.manual_seed(0)
X, y = make_windows()
fe, norm, clf = train_pipeline(RawSensorExtractor, ZNormalizer, TorchCNN1D, X, y)
options = [make_windower(), fe, norm, clf]
model = make_model_doc(num_classes=clf.arch["num_classes"])

with open(os.path.join(out, "model.pte"), "wb") as f:
    f.write(buildExecutorchPte(options, model))
manifest = buildExecutorchManifest(options, model)
with open(os.path.join(out, "manifest.json"), "w") as f:
    json.dump(manifest, f, indent=2)

window = np.ascontiguousarray(X[:2, :, 1:], dtype=np.float32)  # two windows (one per class), timestamp column dropped
with torch.no_grad():
    logits = buildExportModule(options)(torch.from_numpy(window)).numpy()
with open(os.path.join(out, "expected.json"), "w") as f:
    json.dump({"windows": window.tolist(), "logits": logits.tolist(), "labels": [int(v) for v in y[:2]]}, f)
print("ok", manifest["input"]["shape"], logits.tolist())
