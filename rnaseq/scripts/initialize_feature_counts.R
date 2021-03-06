#initialize_counts.R
#prepare reads for DESeq and get gist of data

library('DESeq2')
library('cowplot')
theme_set(theme_cowplot())
library('tidyverse')
rm(list=ls())
source('functions.R')


#upload read counts from htseq
counts = read.table("rnaseq/all_featureCounts_geneCounts.tsv", header = T, row.names='Geneid')
counts = counts[,6:ncol(counts)]
head(counts)
length(unique(colnames(counts)))


#remove non-gene objects from counts data
dim(counts)
tots = apply(counts, 2, sum)
print(paste("Mean read count per sample =", paste(round(mean(tots) / 1e6, 2), "million reads")))


#remove genes with low coverage
cut=3
cc=counts
means=apply(cc,1,mean)
table(means>cut)
counts=cc[means>cut,]



#SET UP COLDATA
#first revise the miss-sexed individuals
sample = colnames(counts)
sra = read_csv('metadata/mySraRunTable.csv')
length(sample)
sum(sample %in% sra$Sample_Name)
sum(sample %in% sra$Run)
keep1 = sra %>% 
  filter(Sample_Name %in% sample)
keep2 = sra %>% 
  filter(Run %in% sample)
sra = rbind(keep1,keep2) %>% 
  filter(!duplicated(Sample_Name)) %>% 
  mutate(mysample = if_else(Run %in% sample,
                            Run,
                            Sample_Name)) %>% 
  data.frame()
rownames(sra) = sra$mysample
nrow(sra)

coldata=sra[sample,] %>% 
  dplyr::select(Organism, sex)

#remove spaces from Organism names
coldata$Organism = sub(' ', '_', coldata$Organism)
coldata
nrow(coldata)


#------- GET RAW VARIANCE STABILIZED COUNTS ------------#
#set up input matrix for DESeq
ddsHTSeq<-DESeqDataSetFromMatrix(counts,
	colData = coldata,
	design = formula(~1))

#run DESeq
dds = DESeq(ddsHTSeq)

#get DEseq results
res = results(dds)

#get variance stabilized counts and save them
rld = rlog(dds)
rld.df=assay(rld)
colnames(rld.df) = colnames(counts)

#=====================================================================================
#
#  Code chunk 2
# transpose the dataset you have samples as rows and genes as columns
#=====================================================================================

datExpr0 = as.data.frame(t(rld.df));

#=====================================================================================
#
#  Code chunk 3
#
#=====================================================================================

#check that the dataset doesn't have geneswith too many missing values
#these would likely represent lowly expressed genes and under sequenced samples
library(WGCNA)
gsg = goodSamplesGenes(datExpr0, verbose = 3);
gsg$allOK



#=====================================================================================
#
#  Code chunk 4

#=====================================================================================
#removing genes that were flagged with too many missing values
#note how many genes we have right now
before = ncol(datExpr0)
print(before)


if (!gsg$allOK)
{
  # Optionally, print the gene and sample names that were removed:
  if (sum(!gsg$goodGenes)>0) 
     printFlush(paste("Removing genes:", paste(names(datExpr0)[!gsg$goodGenes], collapse = ", ")));
  if (sum(!gsg$goodSamples)>0) 
     printFlush(paste("Removing samples:", paste(rownames(datExpr0)[!gsg$goodSamples], collapse = ", ")));
  # Remove the offending genes and samples from the data:
  datExpr0 = datExpr0[gsg$goodSamples, gsg$goodGenes]
}
rld.df=t(datExpr0)
rld=rld[rownames(rld.df),]
dim(rld.df)
dim(rld)
nrow(datExpr0)
after = ncol(datExpr0)
print(paste(before - after, "Genes With Too Many Missing Values Were Removed"))

#=====================================================================================
#
#  Code chunk 5
#
#=====================================================================================

#build sample heatmaps 
library(pheatmap)
phm=pheatmap(cor(rld.df), labels_row=coldata$Organism)

#plot pca
NTOP=nrow(counts)
group='Organism'

pca_df = build_pca(rld.df, coldata, ntop = NTOP, pcs = 2)
addx=3
addy=2
pca_df %>% 
  ggplot(aes(x=PC1, y=PC2, color=Organism, shape=sex)) +
  geom_point(size=5) +
  lims(x=c(min(pca_df$PC1)-addx, max(pca_df$PC1+addx)),
       y=c(min(pca_df$PC2)-addy, max(pca_df$PC2+addy)))
  
save(rld.df, coldata, file='rnaseq/results_files/all_rld.Rdata')


#now cluster samples based on gene expression to identify outliers
sampleTree = hclust(dist(datExpr0), method = "average");
# Plot the sample tree: Open a graphic output window of size 12 by 9 inches
# The user should change the dimensions if the window is too large or too small.
sizeGrWindow(12,9)
#pdf(file = "Plots/sampleClustering.pdf", width = 12, height = 9);
par(cex = 0.6);
par(mar = c(0,5,2,0))
plot(sampleTree, main = "Sample clustering to detect outliers", sub="", xlab="", cex.lab = 1.5, cex.axis = 1.5, cex.main = 2)


save(counts, coldata, file="rnaseq/deseqInput.Rdata")
save(rld, coldata, file="rnaseq/rld.Rdata")

