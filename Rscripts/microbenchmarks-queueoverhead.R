library(ggplot2)
library(tidyverse)
library(scales)
library(shades)
library(socviz)

df <- read.csv("../microbenchmarks-queueoverhead.csv", header = FALSE)
colnames(df) <- c("App", "Transport", "Concurrency", "Channels", "Monotonic", "Parallelism", "Affinity", "Size", "Num", "Latency", "Time")
df <- transform(df, Time = round(as.numeric(Time) / 1000), digits = 2)

df1 <- subset(df, (
  # (Transport == "disterl" & Channels == 1 & Parallelism == 1 & Affinity == "false") |
  #   (Transport == "partisan" & Channels == 1 & Parallelism == Concurrency & Affinity == "false") |
  #  (Transport == "partisan" & Channels == 1 & Parallelism == 1 & Affinity == "false") |
  (Transport == "partisan" & Channels == 4 & Affinity == "true")
  # (Transport == "partisan" & Channels == 4 & Parallelism == Concurrency & Affinity == "true") 
)
& (Size == 524288 & Latency == "1" & is.element(Concurrency, c(128))))
df1$Concurrency <- factor(df1$Concurrency)
df1$Experiment <- paste("partisan parallel affinitized")

#sample_n(df1, 96000)

ggplot(data = df1, aes(x = factor(Parallelism), y = Time, fill = Experiment)) +
  geom_jitter(alpha=0.15, position = position_jitterdodge(jitter.width = 0.25)) +
  # geom_boxplot() + 
  # theme_grey(base_size = 14) + 
  ylab("Milliseconds / RT Request") + 
  xlab("# of Actors") +
  #scale_y_continuous(trans='log2') + 
  #annotation_logticks(base = 2, sides = "l") +
  ggtitle("512KB Payload, 1ms RTT Latency, 128 Actors") +
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


ggsave("../Microbenchmarks-QueueOverhead-black.png", dpi = 400)
