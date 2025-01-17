##############################################################################################################################
#This script carries out the steps involved in analysis of RNAseq data.  
#depending on your data and interests, different parts of this script may not apply to you
##############################################################################################################################
#begin by downloading the packages you'll need for this analysis
#you'll never need to do this again
source("http://bioconductor.org/biocLite.R")
biocLite(pkgs=c("Rsubread", "limma", "edgeR", "ShortRead", "ggvis", "ggplot2", "reshape2", "dplyr"))

y#begin by loading the packages required for RNAseq data
#packages need to be loaded in each new R session as they are needed
library(Rsubread)
library(limma)
library(edgeR)
library(ShortRead)
options(digits=2)

#read in your study design file
targets <- read.delim("studyDesign.txt", row.names=NULL)
targets
groups <- factor(paste(targets$strain, targets$stage, sep="."))
batch <- factor(targets$rep)
#create some more human-readable labels for your samples using the info in this file
sampleLabels <- paste(targets$strain, targets$stage, targets$rep, sep=".")

#set-up your experimental design
design <- model.matrix(~0+groups)
colnames(design) <- levels(groups)
design

# ##############################################################################################################################
# #you can check read quality using shortRead package
# #but I usually find it is better to do this on the sequencer or Illumina's BaseSpace website
# ##############################################################################################################################
# myFastq <- targets$fastq
# #collecting statistics over the files
# qaSummary <- qa("SRR1542919.fastq.gz", type="fastq")
# #create and view a report
# browseURL(report(qaSummary))

##############################################################################################################################
#build index from your reference genome (expect this to take about 20 min on 8G RAM for mouse genome)
#you must have already downloaded the fasta file for your genome of interest and have it in the working directory
#this only needs to be done once, then index can be reused for future alignments
##############################################################################################################################
buildindex(basename="TgME49",reference="ToxoDB-24_TgondiiME49_Genome.fasta", colorspace=TRUE)

##############################################################################################################################
#align your reads (in the fastq files) to your indexed reference genome that you created above
#expect this to take about 45min for a single fastq file containing 25 million reads
#the output from this is a .bam file for each of your original fastq files
##############################################################################################################################
reads <- targets$fastq[13:18]
align(index="TgME49", readfile1=reads, input_format="gzFASTQ",output_format="BAM", color2base=TRUE,
      output_file=targets$output[13:18], tieBreakHamming=TRUE, unique=TRUE, indels=5, nthreads=8)

##############################################################################################################################
#use the 'featureCounts' function to summarize read counts to genomic features (exons, genes, etc)
#will take about 1-2min per .bam file.
#for total transcriptome data summarized to mouse/human .gtf, expect about 50-60% of reads summarize to genes (rest is non-coding)
##############################################################################################################################
#read in text file with bam file names
myBAM <- targets$output
#summarize aligned reads to genomic features (i.e. exons)
fc <- featureCounts(files=myBAM, annot.ext="ToxoDB-24_TgondiiME49.gff", 
                    isGTFAnnotationFile=TRUE, useMetaFeatures=TRUE, strandSpecific=1, 
                    GTF.attrType="ID", GTF.featureType="gene", nthreads=8)
#use the 'DGEList' function from EdgeR to make a 'digital gene expression list' object
DGEList <- DGEList(counts=fc$counts, genes=fc$annotation)
save(DGEList, file="DGEList")



##############################################################################################################################
#beginning of Toxo13 Genomics Workshop
##############################################################################################################################
load("DGEList")
#let's look at the DGEList object. What are its elements, and why might they be important?
DGEList
#retrieve all your gene/transcript identifiers from this DGEList object
myGeneIDs <- DGEList$genes$GeneID

##############################################################################################################################
#Normalize unfiltered data using 'voom' function in Limma package
#This will normalize based on the mean-variance relationship
#will also generate the log2 of counts per million based on the size of each library (also a form of normalization)
##############################################################################################################################
normData.unfiltered <- voom(DGEList, design, plot=TRUE)
exprs.unfiltered <- normData.unfiltered$E
#note that because you're now working with Log2 CPM, much of your data will be negative number (log2 of number smaller than 1 is negative) 
head(exprs.unfiltered)

#if you need RPKM for your unfiltered, they can generated as follows
#Although RPKM are commonly used, not really necessary since you don't care to compare two different genes within a sample
rpkm.unfiltered <- rpkm(DGEList, DGEList$genes$Length)
rpkm.unfiltered <- log2(rpkm.unfiltered + 0.5)
dim(rpkm.unfiltered)

##############################################################################################################################
#Filtering your dataset and normalize this
#Only keep in the analysis those genes which had >10 reads per million mapped reads in at least two libraries.
##############################################################################################################################
cpm.matrix.filtered <- rowSums(cpm(DGEList) > 10) >= 2
DGEList.filtered <- DGEList[cpm.matrix.filtered,]
dim(DGEList.filtered)

normData.filtered <- voom(DGEList.filtered, design, plot=TRUE)
exprs.filtered <- normData.filtered$E
#note that because you're now working with Log2 CPM, much of your data will be negative number (log2 of number smaller than 1 is negative) 
head(exprs.filtered)

rpkm.filtered <- rpkm(DGEList.filtered, DGEList.filtered$genes$Length) #if you prefer, can use 'cpm' instead of 'rpkm' here
rpkm.filtered <- log2(rpkm.filtered + 1)

###############################################################################################
#explore your data using some standard approaches
###############################################################################################
#choose color scheme for graphs
cols.ALL <- topo.colors(n=18, alpha=1)
hist(exprs.filtered, xlab = "log2 expression", main = "normalized data - histograms", col=cols.ALL)
boxplot(exprs.filtered, ylab = "normalized log2 expression", main = "non-normalized data - boxplots", col=cols.ALL)

#view sample relationships using a hierarchical clustering dendogram
distance <- dist(t(exprs.filtered),method="maximum") # options for computing distance matrix are: "euclidean", "maximum", "manhattan", "canberra", "binary" or "minkowski". 
clusters <- hclust(distance, method = "average") #options for clustering method: "ward", "single", "complete", "average", "mcquitty", "median" or "centroid".
plot(clusters, label=sampleLabels)

###############################################################################################
#Principal component analysis of the filtered data matrix
###############################################################################################
pca.res <- prcomp(t(exprs.filtered), scale.=F, retx=T)
ls(pca.res)
summary(pca.res) # Prints variance summary for all principal components.
head(pca.res$rotation) #$rotation shows you how much each GENE influenced each PC (callled 'eigenvalues', or loadings)
head(pca.res$x) #$x shows you how much each SAMPLE influenced each PC (called 'scores')
plot(pca.res, las=1)
pc.var<-pca.res$sdev^2 #sdev^2 gives you the eigenvalues
pc.per<-round(pc.var/sum(pc.var)*100, 1)
pc.per

#make some graphs to visualize your PCA result
library(ggplot2)
#lets first plot any two PCs against each other
#turn your scores for each gene into a data frame
data.frame <- as.data.frame(pca.res$x)
ggplot(data.frame, aes(x=PC1, y=PC2, colour=factor(groups))) +
  geom_point(size=5) +
  theme(legend.position="right")

#create a 'small multiples' chart to look at impact of each variable on each pricipal component
library(reshape2)
melted <- cbind(groups, melt(pca.res$x[,1:3]))
#look at your 'melted' data
ggplot(melted) +
  geom_bar(aes(x=Var1, y=value, fill=groups), stat="identity") +
  facet_wrap(~Var2)


###############################################################################################
#Cleaning up and graphing your data
###############################################################################################
#for creating graphics, we'll use the ggplot2 and ggvis packages which employ a 'grammar of graphics' approach
#load the packages
library(ggplot2)
library(dplyr)
library(ggvis)

#clean-up data table
exprs.filtered.dataframe <- as.data.frame(exprs.filtered)
colnames(exprs.filtered.dataframe)
head(exprs.filtered.dataframe)
colnames(exprs.filtered.dataframe) <- sampleLabels
geneID <- rownames(exprs.filtered.dataframe)
#use the dplyr 'mutate' command to get averages and fold changes for all your replicates
myData <- mutate(exprs.filtered.dataframe,
                 #insert columns that average your replicates
                 RH.tachy.AVG = (RH.tachy.rep1 + RH.tachy.rep2 + RH.tachy.rep3)/2,
                 PLK.tachy.AVG = (PLK.tachy.rep1 + PLK.tachy.rep2 + PLK.tachy.rep3)/2,
                 CTG.tachy.AVG = (CTG.tachy.rep1 + CTG.tachy.rep2 + CTG.tachy.rep3)/2,
                 RH.brady.AVG = (RH.brady.rep1 + RH.brady.rep2 + RH.brady.rep3)/2,
                 PLK.brady.AVG = (PLK.brady.rep1 + PLK.brady.rep2 + PLK.brady.rep3)/2,
                 CTG.brady.AVG = (CTG.brady.rep1 + CTG.brady.rep2 + CTG.brady.rep3)/2,
                 #now add fold-change columns based on the averages calculated above
                 PLK.vs.RH.tachy = (PLK.tachy.AVG - RH.tachy.AVG),
                 CTG.vs.RH.tachy = (CTG.tachy.AVG - RH.tachy.AVG),
                 PLK.vs.CTG.tachy = (PLK.tachy.AVG - CTG.tachy.AVG),
                 brady.vs.tachy.RH = (RH.brady.AVG - RH.tachy.AVG),
                 brady.vs.tachy.PLK = (PLK.brady.AVG - PLK.tachy.AVG),
                 brady.vs.tachy.CTG = (CTG.brady.AVG - CTG.tachy.AVG),
                 geneID)

#take a look at your new spreadsheet
head(myData)
#use dplyr "arrange" and "select" functions to sort by LogFC column of interest (arrange) 
#and then display only the columns of interest (select) to see the most differentially expressed genes
myData.sort <- myData %>%
  arrange(desc(brady.vs.tachy.PLK)) %>%
  select(geneID, PLK.tachy.AVG, PLK.brady.AVG)
head(myData.sort)


#use dplyr "filter" and "select" functions to pick out genes of interest (filter)
#and again display only columns of interest (select)
#filter based on specific Toxo gene IDs
myData.filter <- myData %>%
  filter(geneID=="TGME49_207130" | geneID=="TGME49_208130") %>%
  select(geneID, PLK.tachy.AVG, PLK.brady.AVG)
head(myData.filter)


#filtering based on expression level or fold change
myData.filter <- myData %>%
  filter((abs(PLK.vs.RH.tachy) >= 1) | 
           (abs(CTG.vs.RH.tachy) >= 1) | 
           (abs(PLK.vs.CTG.tachy) >= 1))%>%
  select(geneID, RH.tachy.AVG, PLK.tachy.AVG, CTG.tachy.AVG)
head(myData.filter)

#create a basic scatterplot using ggplot
ggplot(myData, aes(x=RH.tachy.AVG, y=CTG.tachy.AVG)) +
  geom_point(shape=1) +
  geom_point(size=4)

#define a tooltip that shows gene symbol and Log2 expression data when you mouse over each data point in the plot
tooltip <- function(data, ...) {
  paste0("<b>","Symbol: ", data$geneID, "</b><br>",
         "RH.tachy.AVG: ", data$RH.tachy.AVG, "<br>",
         "CTG.tachy.AVG: ", data$CTG.tachy.AVG)
}

#plot the interactive graphic
myData %>% 
  ggvis(x= ~RH.tachy.AVG, y= ~CTG.tachy.AVG, key := ~geneID) %>% 
  layer_points(fill = ~CTG.vs.RH.tachy) %>%
  add_tooltip(tooltip)

#Workshop ends here, but feel free to continue with differential gene expression below on your own time
###############################################################################################
# use Limma to find differentially expressed genes between two or more conditions
###############################################################################################
# fit the linear model to your filtered expression data
library(limma)
fit <- lmFit(exprs.filtered, design)

# set up a contrast matrix based on the pairwise comparisons of interest
contrast.matrix.strains <- makeContrasts(RHvsCTG = RH.tachy - CTG.tachy, RHvsPLK = RH.tachy - PLK.tachy, CTGvsPLK = CTG.tachy - PLK.tachy, levels=design)
contrast.matrix.stages <- makeContrasts(RH = RH.tachy - RH.brady, PLK = PLK.tachy - PLK.brady, CTG = CTG.tachy - CTG.brady, levels=design)

# check each contrast matrix
contrast.matrix.strains
contrast.matrix.stages

# extract the linear model fit for the contrast matrix that you just defined above
fits.strains <- contrasts.fit(fit, contrast.matrix.strains)
fits.stages <- contrasts.fit(fit, contrast.matrix.stages)

#get bayesian stats for your linear model fit
ebFit.strains <- eBayes(fits.strains)
ebFit.stages <- eBayes(fits.stages)

###############################################################################################
# use the topTable and decideTests functions to see the differentially expressed genes
###############################################################################################

# use topTable function to take a look at the hits
myTopHits <- topTable(ebFit.strains, adjust ="BH", coef=2, number=50, sort.by="logFC")
myTopHits

# use the 'decideTests' function to show Venn diagram for all diffexp genes for up to three comparisons
results <- decideTests(ebFit.strains, method="global", adjust.method="BH", p.value=0.01, lfc=1)
#stats <- write.fit(ebFit)
vennDiagram(results, include="both") #all pairwise comparisons on a B6 background

# take a look at what the results of decideTests looks like
results

# now pull out probeIDs from selected regions of the Venn diagram.  In this case, I want all genes in the venn.
diffData <- normData.filtered[results[,1] !=0 | results[,2] !=0 | results[,3] !=0]
diffData <- diffData$E
head(diffData)
dim(diffData)
# print out results to a table
write.table(results.ALL, "diffGenes_2fold.txt", sep="\t", quote=FALSE)
