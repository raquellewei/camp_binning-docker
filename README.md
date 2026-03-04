![Version](https://img.shields.io/badge/version-0.11.1-brightgreen)

## Overview

This module is designed to function as both a standalone MAG binning pipeline as well as a component of the larger CAMP metagenome analysis pipeline. As such, it is both self-contained (ex. instructions included for the setup of a versioned environment, etc.), and seamlessly compatible with other CAMP modules (ex. ingests and spawns standardized input/output config files, etc.).

The design philosophy is to replicate the functionality of [MetaWRAP](https://github.com/bxlab/metaWRAP) with better dependency conflict management and improved integration with new binning algorithms.

**Binners included**: MetaBAT2, CONCOCT, SemiBin, MaxBin2, VAMB (and optionally MetaBinner — see below), refined by DAS Tool.

---

## Installation

### Option 1: Singularity/Apptainer (Recommended — HPC & Linux servers)

No conda setup required. Pull the image directly from Docker Hub:

```bash
singularity pull camp-binning.sif docker://raquelle70679/camp-binning:latest
```

Run the built-in test to verify (no external databases needed — MetaBinner is disabled by default):

```bash
singularity run --bind ~/CAMP/test_out:/data/test_out camp-binning.sif test
```

> **Note:** Apptainer is the new name for Singularity (v3.9+). Commands are identical — just replace `singularity` with `apptainer`.

### Option 2: Docker (Cloud VMs & local machines)

```bash
docker pull raquelle70679/camp-binning:latest
```

Or build from this repo:

```bash
git clone https://github.com/raquellewei/camp_binning-docker
cd camp_binning-docker
docker build --platform linux/amd64 -t camp-binning .
```

### Option 3: Local conda install

See the [original upstream repo](https://github.com/Meta-CAMP/camp_binning) for conda-based local installation instructions using `setup.sh`.

---

## Using the Container

### Input

Prepare a `samples.csv` with absolute paths **as they will appear inside the container**:

```
sample_name,illumina_ctg,illumina_fwd,illumina_rev
sample1,/data/input/sample1.fasta,/data/input/sample1_1.fastq.gz,/data/input/sample1_2.fastq.gz
```

The `illumina_ctg` column should contain assembled contigs (e.g. output from the `camp_short-read-assembly` module).

### Output

- `/data/output/binning/final_reports/samples.csv` — output config for the next CAMP module
- `/data/output/binning/1_metabat2/<sample>/bins/` — MetaBAT2 MAGs
- `/data/output/binning/2_concoct/<sample>/bins/` — CONCOCT MAGs
- `/data/output/binning/3_semibin/<sample>/bins/` — SemiBin MAGs
- `/data/output/binning/4_maxbin2/<sample>/bins/` — MaxBin2 MAGs
- `/data/output/binning/6_vamb/<sample>/bins/` — VAMB MAGs
- `/data/output/binning/7_dastool/<sample>/bins/` — DAS Tool refined MAGs
- `/data/output/binning/final_reports/bin_stats.csv` — per-bin statistics
- `/data/output/binning/final_reports/bin_summ.csv` — per-sample summary

---

## Singularity Usage

### Running the Pipeline

```bash
singularity run \
    --bind /path/to/your/data:/data/input \
    --bind /path/to/your/output:/data/output \
    --bind /path/to/your/config:/data/config \
    camp-binning.sif run \
    -c 10 \
    -d /data/output \
    -s /data/config/samples.csv
```

### Running on a Slurm Cluster

```bash
sbatch << 'EOF'
#!/bin/bash
#SBATCH --job-name=camp-binning
#SBATCH --cpus-per-task=20
#SBATCH --mem=120G
#SBATCH --output=camp-binning-%j.log

singularity run \
    --bind /path/to/your/data:/data/input \
    --bind /path/to/your/output:/data/output \
    --bind /path/to/your/config:/data/config \
    camp-binning.sif run \
    -c 20 \
    -d /data/output \
    -s /data/config/samples.csv
EOF
```

### Running the Built-in Test

The test runs 5 binners (MetaBAT2, CONCOCT, SemiBin, MaxBin2, VAMB) + DAS Tool on a small human gut microbiome dataset. Expected runtime: ~40 minutes with 10 threads, 40 GB RAM.

```bash
singularity run \
    --bind ~/CAMP/test_out:/data/test_out \
    camp-binning.sif test
```

### Cleanup Intermediate Files

After reviewing your bins, remove large intermediate files (coverage files, fragment FASTAs, etc.):

```bash
singularity run \
    --bind /path/to/your/output:/data/output \
    --bind /path/to/your/config:/data/config \
    camp-binning.sif cleanup \
    -d /data/output \
    -s /data/config/samples.csv
```

### Debugging

```bash
singularity shell camp-binning.sif
conda run -n binning python /opt/camp/workflow/binning.py --help
```

---

## MetaBinner (Optional — Requires CheckM1 Database)

MetaBinner is pre-installed in the image but **disabled by default** (`use_metabinner: False`) because it requires the CheckM1 database (~1.5 GB) which cannot be bundled in the image.

### Step 1: Download CheckM1 Database

```bash
mkdir -p ~/CAMP/ref/checkm1
cd ~/CAMP/ref/checkm1
wget https://data.ace.uq.edu.au/public/CheckM_databases/checkm_data_2015_01_16.tar.gz
tar -xzf checkm_data_2015_01_16.tar.gz
rm checkm_data_2015_01_16.tar.gz
```

### Step 2: Create a Custom parameters.yaml

```yaml
conda_prefix: '/opt/conda/envs'

min_contig_len:  2500
min_metabat_len: 2500
fragment_size:   2500
overlap_size:    1000
min_bin_size:    100000
test_flags:      ''
model_environment: 'human_gut'

# Enable MetaBinner
use_metabinner:  True
metabinner_env:  '/opt/conda/envs/metabinner'
checkm1_db:      '/data/ref/checkm1'

dastool_threshold: 0.5
```

### Step 3: Run with CheckM1 Mounted

```bash
singularity run \
    --bind /path/to/your/data:/data/input \
    --bind /path/to/your/output:/data/output \
    --bind /path/to/your/config:/data/config \
    --bind ~/CAMP/ref/checkm1:/data/ref/checkm1 \
    camp-binning.sif run \
    -c 10 \
    -d /data/output \
    -s /data/config/samples.csv \
    -p /data/config/parameters.yaml
```

---

## Docker Usage

### Running the Pipeline

```bash
docker run \
    -v /path/to/your/data:/data/input \
    -v /path/to/your/output:/data/output \
    -v /path/to/your/config:/data/config \
    raquelle70679/camp-binning:latest run \
    -c 10 \
    -d /data/output \
    -s /data/config/samples.csv
```

### Running the Built-in Test

```bash
docker run --rm \
    -v ~/CAMP/test_out:/data/test_out \
    raquelle70679/camp-binning:latest test
```

**Options:**

| Flag | Description |
|------|-------------|
| `-c` | Number of CPU cores (default: 1; use 10-20 for real datasets) |
| `-d` | Working directory inside the container |
| `-s` | Path to `samples.csv` inside the container |
| `-p` | Path to a custom `parameters.yaml` (optional) |
| `-r` | Path to a custom `resources.yaml` (optional) |
| `--dry_run` | Print workflow commands without executing |
| `--unlock` | Remove a lock on the working directory after a failed run |

---

## Key Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `min_contig_len` | `2500` | Minimum contig length for binning |
| `min_metabat_len` | `2500` | Minimum contig length for MetaBAT2 |
| `fragment_size` | `2500` | Fragment size for CONCOCT |
| `overlap_size` | `1000` | Overlap size for CONCOCT fragmentation |
| `min_bin_size` | `100000` | Minimum bin size for VAMB (bytes) |
| `model_environment` | `'human_gut'` | SemiBin pre-trained model environment |
| `use_metabinner` | `False` | Enable MetaBinner (requires CheckM1 database) |
| `dastool_threshold` | `0.5` | DAS Tool score threshold (decreases on retry) |

**SemiBin environment options**: `human_gut`, `dog_gut`, `ocean`, `soil`, `cat_gut`, `human_oral`, `mouse_gut`, `pig_gut`, `built_environment`, `wastewater`, `chicken_caecum`, `global`

---

## Module Structure

```
└── workflow
    ├── Snakefile
    ├── binning.py
    ├── utils.py
    ├── __init__.py
    └── ext/
        └── scripts/
            ├── Fasta_to_Contig2Bin.sh
            ├── calc_bin_lens.py
            ├── extract_fasta_bins.py
            ├── gen_kmer.py
            ├── merge_cutup_clustering.py
            └── split_vamb_output.py
```

---

## Credits

- This package was created with [Cookiecutter](https://github.com/cookiecutter/cookiecutter) as a simplified version of the [project template](https://github.com/audreyr/cookiecutter-pypackage).
- Original upstream repo: [Meta-CAMP/camp_binning](https://github.com/Meta-CAMP/camp_binning)
- Free software: MIT
- Documentation: https://camp-documentation.readthedocs.io/en/latest/binning.html
