import os
from os import path
import pandas as pd
from collections import OrderedDict

if not workflow.overwrite_configfiles:
    configfile: "config.yml"
workdir: path.join(config["workdir_top"], config["pipeline"])

WORKDIR = path.join(config["workdir_top"], config["pipeline"])
RESDIR =  config["resdir"]
SNAKEDIR = path.dirname(workflow.snakefile)
PY2_EXEC = "python2 {}/scripts".format(SNAKEDIR)

include: "snakelib/utils.snake"

control_samples = config["control_samples"]
treated_samples = config["treated_samples"]

all_samples = config["control_samples"].copy()
all_samples.update(config["treated_samples"])
datasets = [path.basename(x).rsplit(".", 1)[0] for x in all_samples.values()]

rule all:
    input:
        ver = "versions.txt",
        count_tsvs = expand("counts/{sample}_salmon/quant.sf", sample=all_samples.keys()),
        merged_tsv = "merged/all_counts.tsv",
        coldata = "de_analysis/coldata.tsv",
        de_params = "de_analysis/de_params.tsv",
        res_dge = "de_analysis/results_dge.pdf",
        dtu_pdf = "de_analysis/dtu_plots.pdf",

rule dump_versions:
    output:
        ver = "versions.txt"
    conda: "env.yml"
    shell:"""
    conda list > {output.ver} 
    """

rule count_reads:
    input:
        bam = lambda wildcards: all_samples[wildcards.sample], 
        trs = config["transcriptome"],
    output:
        tsv = "counts/{sample}_salmon/quant.sf",
    params:
        tsv_dir = "counts/{sample}_salmon",
        libtype = config["salmon_libtype"],
    conda: "env.yml"
    threads: config["threads"]
    shell: """
        salmon quant --noErrorModel -p {threads} -t {input.trs} -l {params.libtype} -a {input.bam} -o {params.tsv_dir}
    """

rule merge_counts:
    input:
        count_tsvs = expand("counts/{sample}_salmon/quant.sf", sample=all_samples.keys()),
    output:
        tsv = "merged/all_counts.tsv"
    conda: "env.yml"
    shell:"""
    {SNAKEDIR}/scripts/merge_count_tsvs.py -z -o {output.tsv} {input.count_tsvs}
    """

rule write_coldata:
    input:
    output:
        coldata = "de_analysis/coldata.tsv"
    run:
        samples, conditions, types = [], [], []
        for sample in control_samples.keys():
            samples.append(sample)
            conditions.append("untreated")
            types.append("single-read")
        for sample in treated_samples.keys():
            samples.append(sample)
            conditions.append("treated")
            types.append("single-read")

        df = pd.DataFrame(OrderedDict([('sample', samples),('condition', conditions),('type', types)]))
        df.to_csv(output.coldata, sep="\t", index=False)

rule write_de_params:
    input:
    output:
        de_params = "de_analysis/de_params.tsv"
    run:
        d = OrderedDict()
        d["Annotation"] = [config["annotation"]]  #unnecessary?
        d["min_samps_gene_expr"] = [config["min_samps_gene_expr"]]
        d["min_samps_feature_expr"] = [config["min_samps_feature_expr"]]
        d["min_gene_expr"] = [config["min_gene_expr"]]
        d["min_feature_expr"] = [config["min_feature_expr"]]
        df = pd.DataFrame(d)
        df.to_csv(output.de_params, sep="\t", index=False)


rule de_analysis:
    input:
        de_params = rules.write_de_params.output.de_params,
        coldata = rules.write_coldata.output.coldata,
        tsv = rules.merge_counts.output.tsv,
    output:
        res_dge = "de_analysis/results_dge.tsv",
        pdf_dge = "de_analysis/results_dge.pdf",
        res_dtu_gene = "de_analysis/results_dtu_gene.tsv",
        res_dtu_trs = "de_analysis/results_dtu_transcript.tsv",
        res_dtu_stager = "de_analysis/results_dtu_stageR.tsv",
        flt_counts = "merged/all_counts_filtered.tsv",
        flt_counts_gens = "merged/all_gene_counts.tsv",
    conda: "env.yml"
    shell:"""
    {SNAKEDIR}/scripts/de_analysis.R
    """

rule plot_dtu_res:
    input:
        res_dtu_stager = "de_analysis/results_dtu_stageR.tsv",
        flt_counts = "merged/all_counts_filtered.tsv",
    output:
        dtu_pdf = "de_analysis/dtu_plots.pdf",
    conda: "env.yml"
    shell: """
    {SNAKEDIR}/scripts/plot_dtu_results.R
    """


