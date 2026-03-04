# =============================================================================
# CAMP MAG Binning Pipeline
# =============================================================================
# Base image: continuumio/miniconda3 (Debian-based, conda pre-installed)

# -----------------------------------------------------------------------------
# Step 1: Base Image
# -----------------------------------------------------------------------------
FROM continuumio/miniconda3:latest

LABEL maintainer="raquellewei"
LABEL description="CAMP MAG Binning Pipeline"
LABEL version="0.11.1"

# -----------------------------------------------------------------------------
# Step 2: System Dependencies
# -----------------------------------------------------------------------------
# - wget/curl        : downloading data at runtime
# - gzip/bzip2       : compressing/decompressing files
# - perl             : required by MaxBin2 (run_MaxBin.pl) and other tools
# - default-jre      : may be required by DAS Tool's bundled dependencies
# - procps           : allows Snakemake to monitor system resources
# - bc               : arithmetic in dastool_refinement shell (threshold decrement)
RUN apt-get update && apt-get install -y --no-install-recommends \
        wget \
        curl \
        gzip \
        bzip2 \
        perl \
        default-jre-headless \
        procps \
        bc \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Step 3: Main CAMP Conda Environment
# -----------------------------------------------------------------------------
# The main env runs: Snakemake, the CLI, rules without a conda: directive
# (map_reads, sort_reads via bowtie2/samtools), and the concoct_calculate_depth
# run: block (needs pysam).
COPY configs/conda/binning.yaml /tmp/conda/binning.yaml

RUN conda env create -f /tmp/conda/binning.yaml \
    && conda clean -afy

# -----------------------------------------------------------------------------
# Step 4: Tool-Specific Conda Environments
# -----------------------------------------------------------------------------
# Each binner lives in an isolated conda environment, pre-built here so the
# container needs no internet access at pipeline runtime.
#
# Snakemake activates them via conda: directives in the Snakefile:
#   conda: "metabat2"  → /opt/conda/envs/metabat2   (MetaBAT2 + depth calc)
#   conda: "concoct"   → /opt/conda/envs/concoct
#   conda: "semibin"   → /opt/conda/envs/semibin     (SemiBin1)
#   conda: "maxbin2"   → /opt/conda/envs/maxbin2
#   conda: "metabinner"→ /opt/conda/envs/metabinner  (disabled by default)
#   conda: "vamb"      → /opt/conda/envs/vamb
#   conda: "das_tool"  → /opt/conda/envs/das_tool    (ensemble refinement)
#
# MetaBinner is pre-built even though it is disabled by default (use_metabinner: False),
# so users who have the CheckM1 database can enable it without rebuilding the image.
COPY configs/conda/metabat2.yaml    /tmp/conda/metabat2.yaml
COPY configs/conda/concoct.yaml     /tmp/conda/concoct.yaml
COPY configs/conda/semibin.yaml     /tmp/conda/semibin.yaml
COPY configs/conda/maxbin2.yaml     /tmp/conda/maxbin2.yaml
COPY configs/conda/metabinner.yaml  /tmp/conda/metabinner.yaml
COPY configs/conda/vamb.yaml        /tmp/conda/vamb.yaml
COPY configs/conda/das_tool.yaml    /tmp/conda/das_tool.yaml

RUN conda env create -f /tmp/conda/metabat2.yaml \
    && conda env create -f /tmp/conda/concoct.yaml \
    && conda env create -f /tmp/conda/semibin.yaml \
    && conda env create -f /tmp/conda/maxbin2.yaml \
    && conda env create -f /tmp/conda/metabinner.yaml \
    && conda env create -f /tmp/conda/vamb.yaml \
    && conda env create -f /tmp/conda/das_tool.yaml \
    && conda clean -afy

# -----------------------------------------------------------------------------
# Step 5: Copy Pipeline Code
# -----------------------------------------------------------------------------
# Layout inside the container:
#   /opt/camp/workflow/   — Snakefile, CLI, utils, ext/scripts
#   /opt/camp/configs/    — conda yamls, parameters templates, resources
#   /opt/camp/test_data/  — bundled test FASTAs + FASTQs for smoke-testing
WORKDIR /opt/camp

COPY workflow/   ./workflow/
COPY configs/    ./configs/
COPY test_data/  ./test_data/

# Make ext scripts executable (Fasta_to_Contig2Bin.sh requires execute permission)
RUN chmod +x /opt/camp/workflow/ext/scripts/Fasta_to_Contig2Bin.sh

# -----------------------------------------------------------------------------
# Step 6: Generate Container-Appropriate Config Files
# -----------------------------------------------------------------------------
# Two configs are written:
#   configs/parameters.yaml   — defaults for real pipeline runs
#   test_data/parameters.yaml — test-specific values (smaller thresholds)
#
# Key container paths:
#   ext           → /opt/camp/workflow/ext
#   conda_prefix  → /opt/conda/envs
#   metabinner_env→ /opt/conda/envs/metabinner  (used if use_metabinner: True)
#   checkm1_db    → /data/ref/checkm1           (user must mount this volume)
#
# MetaBinner is disabled by default. To enable it, create a custom
# parameters.yaml with use_metabinner: True and mount the CheckM1 database.

# Production parameters.yaml
RUN printf '%s\n' \
    "#'''Parameters'''#" \
    "" \
    "ext: '/opt/camp/workflow/ext'" \
    "conda_prefix: '/opt/conda/envs'" \
    "" \
    "# --- binning thresholds --- #" \
    "" \
    "min_contig_len:  2500" \
    "min_metabat_len: 2500" \
    "fragment_size:   2500" \
    "overlap_size:    1000" \
    "min_bin_size:    100000" \
    "test_flags:      ''" \
    "" \
    "# --- SemiBin --- #" \
    "" \
    "# Pre-trained environment models are bundled with SemiBin." \
    "# Options: human_gut, dog_gut, ocean, soil, cat_gut, human_oral," \
    "#          mouse_gut, pig_gut, built_environment, wastewater, chicken_caecum, global" \
    "model_environment: 'human_gut'" \
    "" \
    "# --- MetaBinner (disabled by default) --- #" \
    "# Requires the CheckM1 database (~1.5 GB). To enable:" \
    "#   1. Download: see README for instructions" \
    "#   2. Mount: --bind /path/to/checkm1:/data/ref/checkm1" \
    "#   3. Set use_metabinner: True in your parameters.yaml" \
    "" \
    "use_metabinner:  False" \
    "metabinner_env:  '/opt/conda/envs/metabinner'" \
    "checkm1_db:      '/data/ref/checkm1'" \
    "" \
    "# --- DAS Tool --- #" \
    "" \
    "dastool_threshold: 0.5" \
    > /opt/camp/configs/parameters.yaml

# Test parameters.yaml (smaller thresholds for the bundled test dataset)
RUN printf '%s\n' \
    "#'''Parameters (test)'''#" \
    "" \
    "ext: '/opt/camp/workflow/ext'" \
    "conda_prefix: '/opt/conda/envs'" \
    "" \
    "# Reduced thresholds for the small test FASTA / FASTQ files" \
    "min_contig_len:  500" \
    "min_metabat_len: 1500" \
    "fragment_size:   1500" \
    "overlap_size:    0" \
    "min_bin_size:    100" \
    "test_flags:      '-e 2 -t 2 -q 1'" \
    "" \
    "model_environment: 'human_gut'" \
    "" \
    "# MetaBinner disabled for test (no CheckM1 database required)" \
    "use_metabinner:  False" \
    "metabinner_env:  '/opt/conda/envs/metabinner'" \
    "checkm1_db:      '/data/ref/checkm1'" \
    "" \
    "dastool_threshold: 0.5" \
    > /opt/camp/test_data/parameters.yaml

# Generate test_data/samples.csv with container-correct absolute paths.
# Uses the MetaSPAdes assembly as the test contig file.
RUN printf '%s\n' \
    "sample_name,illumina_ctg,illumina_fwd,illumina_rev" \
    "uhgg_metaspades,/opt/camp/test_data/uhgg.metaspades.fasta,/opt/camp/test_data/uhgg_1.fastq.gz,/opt/camp/test_data/uhgg_2.fastq.gz" \
    > /opt/camp/test_data/samples.csv

# -----------------------------------------------------------------------------
# Step 7: Volume Mount Points
# -----------------------------------------------------------------------------
# /data/input    — user's FASTQ and FASTA files
# /data/output   — working directory for real pipeline runs
# /data/config   — optional: override samples.csv or parameters.yaml
# /data/ref      — optional: CheckM1 database at /data/ref/checkm1
#                  (only needed when use_metabinner: True)
# /data/test_out — dedicated output directory for the built-in test command
RUN mkdir -p /data/input /data/output /data/config /data/ref /data/test_out

VOLUME ["/data/input", "/data/output", "/data/config", "/data/ref", "/data/test_out"]

# -----------------------------------------------------------------------------
# Step 8: Entrypoint
# -----------------------------------------------------------------------------
# All pipeline tools are invoked through the 'binning' conda environment.
# ENTRYPOINT is fixed; CMD provides the default (--help).
#
# Usage examples:
#   # Run the pipeline
#   singularity run --bind ... camp-binning.sif run \
#       -c 10 -d /data/output -s /data/config/samples.csv
#
#   # Run the built-in test (no external databases needed)
#   singularity run --bind ~/test_out:/data/test_out camp-binning.sif test
#
#   # Enable MetaBinner (requires CheckM1 mount)
#   singularity run \
#       --bind /path/to/checkm1:/data/ref/checkm1 \
#       --bind /path/to/params.yaml:/opt/camp/configs/parameters.yaml \
#       camp-binning.sif run ...
ENTRYPOINT ["conda", "run", "--no-capture-output", "-n", "binning", \
            "python", "/opt/camp/workflow/binning.py"]
CMD ["--help"]
