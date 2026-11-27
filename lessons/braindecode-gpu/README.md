# Fine-tune an EEG foundation model on an NSG GPU

How much does adapting an EEG foundation model improve motor imagery decoding, and what does it cost in GPU memory? Compare a frozen REVE backbone with low-rank adaptation (LoRA) on the same four-class BCI Competition IV 2a benchmark. The job uses [Braindecode](https://braindecode.org/) models and the [OpenEEGBench](https://github.com/braindecode/OpenEEGBench) evaluation pipeline.

REVE has about 69 million backbone parameters. Both conditions train a linear classifier. In the frozen condition the backbone stays fixed. LoRA also trains small adapters inside the backbone, which requires backpropagating through it. Before running the job, predict how this will affect peak GPU memory and held-out accuracy.

## 1. Package one job

You need Python 3.11 or later and an [NSG portal account](https://nsgprod.sdsc.edu:8443/portal2/). The planner runs with the Python standard library. The GPU job downloads the public [benchmark dataset](https://huggingface.co/datasets/braindecode/bcic2a) and [REVE weights](https://huggingface.co/brain-bzh/reve-base) on Expanse. Those pre-windowed benchmark data are hosted on Hugging Face.

```sh
git clone https://github.com/NeuroTechX/nsg-agent-kit.git
cd nsg-agent-kit
python3 sweep/oeb_plan.py plan --name reve-motor-imagery \
  --datasets bcic2a --backbones reve --strategies frozen lora \
  --heads linear_head --seeds 0 --runtime-hours 2
```

This creates one ZIP at `sweep/oeb/reve-motor-imagery/shards/bcic2a_s0.zip` with two experiments. The [runner](../../sweep/oeb_shard.py) installs the Volta-compatible PyTorch stack into job scratch space and shares the data and model downloads across both experiments.

## 2. Submit through the NSG portal

Under **Data → Upload Data**, upload the ZIP. Under **Tasks → Create New Task**, select the uploaded ZIP and **PyTorch Python on Expanse**. Use these settings.

| Setting | Value |
| --- | --- |
| Main input file | `run.py` |
| Subdirectory | `bcic2a_s0` |
| Nodes and GPUs per node | 1 node, 1 GPU |
| Host memory per node | 96 GB |
| Wall time | 2 hours |

The wall time is the job limit and includes software setup and downloads. The archived training cells took minutes. Queue time varies. See the [portal walkthrough](../../docs/submit-portal.md) for where to find the settings.

## 3. Read the results

When the task finishes, download and extract the output archive. From your checkout, pass the extracted `shard_summary.json` to the report script.

```sh
python3 lessons/braindecode-gpu/report.py /path/to/extracted/bcic2a_s0/shard_summary.json
```

Here are two reference rows from the kit’s [archived NSG benchmark](../../sweep/oeb/public1/leaderboard.csv), using BCI IV 2a, seed 0, and the linear head.

| REVE adaptation | Test balanced accuracy | Training and evaluation | Peak PyTorch GPU allocation | Trainable parameters |
| --- | ---: | ---: | ---: | ---: |
| Frozen backbone | 43.34% | 60 s | 0.50 GiB | 180,228 |
| LoRA | 56.31% | 134 s | 5.53 GiB | 3,078,884 |

Balanced accuracy averages recall across the four classes. A uniform random baseline is 25%. The time and memory columns describe one benchmark cell each. The memory figure measures allocations tracked by PyTorch. The rows record a 30-epoch maximum and learning rate of 0.001 for both conditions. Treat the result as one measured comparison. When the numbers differ, compare the versions, training settings, and runtime metadata in your summary first.

- How many percentage points did LoRA gain in the reference run? How many times more peak GPU memory did it use?
- Why would you keep the test split fixed when you try a new optimization setting? Which split should you use to choose that setting?
- Repeat with fresh seeds and report the spread before drawing a conclusion about adaptation. Try `--seeds 0 1 2` in a new named plan. The planner creates one ZIP per seed. Pass `--seed 1` or `--seed 2` to the report script for those outputs.

## Bring another GPU project

- **Compare models on the same task.** Try one additional Braindecode backbone such as CBraMod with the same dataset, head, and seeds. Find supported configurations and memory limits in the [benchmark notes](../../docs/OPENEEGBENCH.md).
- **Start with public raw EEG from NEMAR.** Use the kit’s [mount and loading examples](../../docs/nemar-data.md) to locate the recording. A new dataset recipe needs explicit labels and a subject- or session-level evaluation split before adding an EEGNet baseline or fine-tuning a pretrained model. The benchmark ZIP above already has its own upstream data and split.
- **Package custom training.** Start from the [PyTorch job template](../../templates/pytorch-gpu/README.md) and [dependency guide](../../docs/dependencies.md). Bring one bounded training or inference experiment first. Capture the split, software versions, GPU memory and elapsed time before expanding the run.
