"""Train and export a TorchVision image classifier from a normalized manifest."""

from __future__ import annotations

import argparse
import csv
import json
import random
import time
from pathlib import Path

import numpy as np
import torch
from PIL import Image
from sklearn.metrics import classification_report
from torch import nn
from torch.utils.data import DataLoader, Dataset
from torchvision import models, transforms


class ManifestDataset(Dataset):
    def __init__(self, rows, transform):
        self.rows, self.transform = rows, transform

    def __len__(self):
        return len(self.rows)

    def __getitem__(self, index):
        row = self.rows[index]
        with Image.open(row["path"]) as image:
            tensor = self.transform(image.convert("RGB"))
        return tensor, int(row["class_index"])


def load_rows(manifest: Path, task: str):
    with manifest.open(newline="", encoding="utf-8") as handle:
        rows = [row for row in csv.DictReader(handle) if row["task"] == task]
    missing = [row["path"] for row in rows if not Path(row["path"]).is_file()]
    if missing:
        raise FileNotFoundError(f"{len(missing)} manifest images are missing; first: {missing[0]}")
    if not rows:
        raise ValueError(f"No {task} records found in {manifest}")
    return rows


def build_model(name: str, classes: int):
    if name == "efficientnet_b0":
        model = models.efficientnet_b0(weights=models.EfficientNet_B0_Weights.DEFAULT)
        model.classifier[1] = nn.Linear(model.classifier[1].in_features, classes)
    else:
        model = models.mobilenet_v3_small(weights=models.MobileNet_V3_Small_Weights.DEFAULT)
        model.classifier[3] = nn.Linear(model.classifier[3].in_features, classes)
    return model


def run_epoch(model, loader, loss_fn, device, optimizer=None):
    training = optimizer is not None
    model.train(training)
    total_loss, correct, count = 0.0, 0, 0
    predictions, targets = [], []
    for images, labels in loader:
        images, labels = images.to(device), labels.to(device)
        if training:
            optimizer.zero_grad(set_to_none=True)
        with torch.set_grad_enabled(training):
            logits = model(images)
            loss = loss_fn(logits, labels)
            if training:
                loss.backward()
                optimizer.step()
        predicted = logits.argmax(1)
        total_loss += loss.item() * labels.size(0)
        correct += (predicted == labels).sum().item()
        count += labels.size(0)
        predictions.extend(predicted.cpu().tolist())
        targets.extend(labels.cpu().tolist())
    return total_loss / count, correct / count, predictions, targets


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--task", choices=("disease", "weed"), required=True)
    parser.add_argument("--architecture", choices=("efficientnet_b0", "mobilenet_v3_small"), default="efficientnet_b0")
    parser.add_argument("--epochs", type=int, default=20)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--learning-rate", type=float, default=3e-4)
    parser.add_argument("--seed", type=int, default=2026)
    parser.add_argument("--output", type=Path, default=Path("ai_training/outputs"))
    parser.add_argument("--onnx", action="store_true")
    args = parser.parse_args()

    random.seed(args.seed); np.random.seed(args.seed); torch.manual_seed(args.seed)
    rows = load_rows(args.manifest, args.task)
    class_names = {int(row["class_index"]): row["class_name"] for row in rows}
    expected = list(range(len(class_names)))
    if sorted(class_names) != expected:
        raise ValueError(f"Class indices must be contiguous from zero; got {sorted(class_names)}")

    train_transform = transforms.Compose([
        transforms.RandomResizedCrop(224, scale=(0.7, 1.0)),
        transforms.RandomHorizontalFlip(), transforms.RandomRotation(12),
        transforms.ColorJitter(0.15, 0.15, 0.15, 0.05), transforms.ToTensor(),
        transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225]),
    ])
    eval_transform = transforms.Compose([
        transforms.Resize(256), transforms.CenterCrop(224), transforms.ToTensor(),
        transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225]),
    ])
    loaders = {}
    for split in ("train", "val", "test"):
        selected = [row for row in rows if row["split"] == split]
        if not selected:
            raise ValueError(f"Manifest has no {split} records")
        loaders[split] = DataLoader(
            ManifestDataset(selected, train_transform if split == "train" else eval_transform),
            batch_size=args.batch_size, shuffle=split == "train", num_workers=0,
        )

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model = build_model(args.architecture, len(class_names)).to(device)
    optimizer = torch.optim.AdamW(model.parameters(), lr=args.learning_rate, weight_decay=1e-4)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=max(args.epochs, 1))
    loss_fn = nn.CrossEntropyLoss(label_smoothing=0.1)
    output = args.output / args.task
    output.mkdir(parents=True, exist_ok=True)
    best_path, best_accuracy = output / "best_state.pt", -1.0
    history = []
    started = time.time()
    for epoch in range(1, args.epochs + 1):
        train_loss, train_accuracy, _, _ = run_epoch(model, loaders["train"], loss_fn, device, optimizer)
        val_loss, val_accuracy, _, _ = run_epoch(model, loaders["val"], loss_fn, device)
        scheduler.step()
        history.append({"epoch": epoch, "train_loss": train_loss, "train_accuracy": train_accuracy,
                        "val_loss": val_loss, "val_accuracy": val_accuracy})
        print(f"epoch={epoch} train_acc={train_accuracy:.4f} val_acc={val_accuracy:.4f}")
        if val_accuracy > best_accuracy:
            best_accuracy = val_accuracy
            torch.save(model.state_dict(), best_path)

    model.load_state_dict(torch.load(best_path, map_location=device, weights_only=True))
    test_loss, test_accuracy, predictions, targets = run_epoch(model, loaders["test"], loss_fn, device)
    report = classification_report(targets, predictions, labels=expected,
                                   target_names=[class_names[i] for i in expected], zero_division=0, output_dict=True)
    model.eval().cpu()
    example = torch.zeros(1, 3, 224, 224)
    torch.jit.trace(model, example).save(str(output / "model.torchscript.pt"))
    if args.onnx:
        try:
            torch.onnx.export(model, example, output / "model.onnx", input_names=["image"],
                              output_names=["logits"], dynamic_axes={"image": {0: "batch"}, "logits": {0: "batch"}},
                              opset_version=18, dynamo=False)
        except Exception as error:
            raise RuntimeError("ONNX export failed. Install compatible onnx and onnxruntime packages.") from error
    metadata = {
        "task": args.task, "architecture": args.architecture, "classes": class_names,
        "best_validation_accuracy": best_accuracy, "test_accuracy": test_accuracy,
        "test_loss": test_loss, "seconds": time.time() - started, "device": str(device),
        "history": history, "classification_report": report,
    }
    (output / "metadata.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    print(f"test_accuracy={test_accuracy:.4f}; exports={output.resolve()}")


if __name__ == "__main__":
    main()

