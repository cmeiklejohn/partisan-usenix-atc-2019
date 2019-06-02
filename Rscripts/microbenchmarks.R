library(ggplot2)
library(tidyverse)
library(scales)
library(shades)
library(socviz)

# df <- read.csv("C:\\Users\\cmeiklej\\source\\repos\\unir-2019-03-28\\microbenchmarks.csv", header = FALSE)
# df <- read.csv("C:\\Users\\cmeiklej\\OneDrive\\Desktop\\usenix-2019-camera-ready-results\\microbenchmarks.csv", header = FALSE)
# df <- read.csv("C:\\Users\\chris\\Documents\\GitHub\\unir\\results-3.csv", header = FALSE)
df <- read.csv("../microbenchmarks.csv", header = FALSE)
colnames(df) <- c("App", "Transport", "Concurrency", "Channels", "Monotonic", "Parallelism", "Affinity", "Size", "Num", "Latency", "Time")
df <- transform(df, Time = round(as.numeric(Time) / 1000, digits = 2))

df1 <- subset(df, (
  # disterl 1 1 false 
  (Transport == "disterl" & Channels == 1 & Parallelism == 1 & Affinity == "false") |
    
    # partisan 1 1 false
    (Transport == "partisan" & Channels == 1 & Parallelism == 1 & Affinity == "false") |
    
    # partisan 1 16 false
    (Transport == "partisan" & Channels == 1 & Parallelism == 16 & Affinity == "false") |
    
    # partisan 1 16 true
    (Transport == "partisan" & Channels == 1 & Parallelism == 16 & Affinity == "true") |
    
    # partisan 4 1 false
    (Transport == "partisan" & Channels == 4 & Parallelism == 1 & Affinity == "false") |
    
    # partisan 4 16 true 
    (Transport == "partisan" & Channels == 4 & Parallelism == 16 & Affinity == "true") 
)
& (Size == 524288 & Latency == "1" & is.element(Concurrency, c(16, 32, 64, 128))))
df1$Concurrency <- factor(df1$Concurrency)
df1$Experiment <- paste("",
                        ifelse(df1$Affinity == "true" & df1$Transport == "partisan" & df1$Channels == 4 & df1$Parallelism == 16, "partisan parallel affinitized (N = 16)",
                               ifelse(df1$Affinity == "true" & df1$Transport == "partisan" & df1$Channels == 1 & df1$Parallelism == 16, "partisan parallel affinitized (N = 16)",
                                      ifelse(df1$Affinity == "false" & df1$Channels == 1 & df1$Transport == "partisan" & df1$Parallelism == 1, "partisan (N = 1)",
                                             ifelse(df1$Affinity == "false" & df1$Channels == 4 & df1$Transport == "partisan" & df1$Parallelism == 1, "partisan w/ channels (N = 1)",
                                                    ifelse(df1$Affinity == "false" & df1$Transport == "partisan" & df1$Channels == 1 & df1$Parallelism == 16, "partisan parallel (N = 16)",
                                                           "disterl"))))))

lighten <- function(color, factor=1.4){
  col <- col2rgb(color)
  col <- col*factor
  col <- rgb(t(col), maxColorValue=255)
  col
}

#sample_n(df1, 96000)

ggplot(data = df1, aes(x = Concurrency, y = Time, fill = Experiment)) +
  geom_jitter(alpha=0.1, position = position_jitterdodge(jitter.width = 0.1), aes(color = Experiment)) +
  geom_boxplot(outlier.shape = NA,  notch = TRUE) +
  # geom_boxplot() + 
  # theme_grey(base_size = 14) + 
  ylab("Milliseconds / RT Request") + 
  xlab("# of Actors") +
  #scale_y_continuous(trans='log2') + 
  #annotation_logticks(base = 2, sides = "l") +
  ggtitle("512KB Payload, 1ms RTT Latency") +
  theme_classic() +
  theme(legend.position = c(0.27, 0.86), 
        panel.grid.major.y = element_line(size = 0.25, linetype = 'solid', colour = "grey60"),
        panel.grid.minor.y = element_line(size = 0.1, linetype = 'solid', colour = "grey80"),
        # legend.background = element_rect(color = "black", fill = "grey90", size = 1, linetype = "solid"),
        plot.title=element_text(size=18),
        axis.text=element_text(size=16),
        axis.title=element_text(size=18),
        legend.title=element_text(size=16, face="bold"), 
        legend.text=element_text(size=16)
  )
  #coord_trans(y='log2')

ggsave("../Microbenchmarks-Final-linear.png", dpi = 400)