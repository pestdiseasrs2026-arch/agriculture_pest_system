# PyTorch model training

This package trains two independent classifiers:

- `disease`: Rice Leaf Diseases plus optional PlantVillage classes.
- `weed`: DeepWeeds using an official five-fold split.

Raw images, generated manifests, checkpoints, and exports are ignored by Git. Review each dataset's licence before deployment.

## Prepare manifests

The DeepWeeds archive must be extracted to `DeepWeeds-master/DeepWeeds-master/images`. PlantVillage is optional and should be extracted as class directories below `PlantVillage`.

```powershell
.\.venv\Scripts\python.exe ai_training\build_manifests.py --fold 0
```

Normalized CSV fields are `path`, `task`, `split`, `class_name`, `class_index`, and `source`. Rice and PlantVillage use deterministic 70/15/15 splits. DeepWeeds uses the selected official train/validation/test fold without reshuffling.

## Train

EfficientNet-B0 disease classifier:

```powershell
.\.venv\Scripts\python.exe ai_training\train.py --manifest ai_training\data\disease_manifest.csv --task disease --architecture efficientnet_b0 --epochs 20
```

MobileNetV3 weed classifier with ONNX export:

```powershell
.\.venv\Scripts\python.exe ai_training\train.py --manifest ai_training\data\weed_manifest.csv --task weed --architecture mobilenet_v3_small --epochs 20 --onnx
```

Each run retains the best validation checkpoint, test metrics, per-class classification report, TorchScript model, and optional ONNX model. Pretrained weights are downloaded by TorchVision on the first run. Do not claim production accuracy from the 120-image rice dataset; expand it with representative field images and perform expert review first.

