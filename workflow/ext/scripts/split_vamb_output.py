# split_vamb_output.py — VAMB v5-compatible
from vamb.vambtools import read_clusters, write_bins, byte_iterfasta
from os import listdir, makedirs
from os.path import join
import shutil, sys
from pathlib import Path

# argv: 1=vae_clusters_unsplit.tsv  2=contigs.fasta  3=minsize  4=outdir  5=binsdir
if len(sys.argv) != 6:
    sys.stderr.write("Usage: split_vamb_output.py <clusters.tsv> <contigs.fasta> <minsize> <outdir> <binsdir>\n")
    sys.exit(2)

clusters_tsv, fasta_path, minsize, outdir, binsdir = sys.argv[1:6]
minsize = int(minsize)

# --- verify header but DO NOT consume it for read_clusters() ---
with open(clusters_tsv, "r") as tsv:
    header = tsv.readline().rstrip("\r\n")
    if header.strip().lower().replace(" ", "") != "clustername\tcontigname":
        raise ValueError(
            f"Unexpected header in {clusters_tsv!r}: '{header}'. "
            "Expected exactly: 'clustername\\tcontigname'"
        )
    tsv.seek(0)  # <<— critical: rewind so read_clusters() can read the header itself
    bins = read_clusters(tsv, min_size=2)

# --- ensure output dirs ---
makedirs(outdir, exist_ok=True)
makedirs(binsdir, exist_ok=True)

# --- Filter bins by minsize ---
# First, we need to get contig lengths to filter by size
contig_lengths = {}
with open(fasta_path, 'rb') as filehandle:
    for record in byte_iterfasta(filehandle, fasta_path):
        contig_lengths[record.identifier] = len(record.sequence)
        # Also store string version for compatibility
        try:
            contig_lengths[record.identifier.decode("utf-8")] = len(record.sequence)
        except Exception:
            pass

# Filter bins by minimum size
filtered_bins = {}
for cluster, contigs in bins.items():
    total_length = sum(contig_lengths.get(contig, 0) for contig in contigs)
    if total_length >= minsize:
        filtered_bins[cluster] = contigs

# --- write per-bin FASTAs then copy/rename ---
# Convert outdir to Path object and pass the original FASTA file
write_bins(Path(outdir), filtered_bins, open(fasta_path, 'rb'), maxbins=10000)

for f in listdir(outdir):
    if f.endswith(".fna"):           # e.g., '1.fna'
        bin_id = f.split(".")[0]
        shutil.copy(join(outdir, f), join(binsdir, f"bin.{bin_id}.fa"))

open(outdir + "_done.txt", "w").write("")
