library(ggplot2)
library(scales)

########################################################################
# KVS 1ms

df <- read.csv("c:\\users\\chris\\GitHub\\unir\\throughput-kvs.csv", header = FALSE)
colnames(df) <- c("App", "Transport", "Concurrency", "Channels", "Monotonic", "Parallelism", "Affinity", "Size", "Num", "Latency", "Time")
df <- transform(df, Time = as.numeric(Time) / 1000)

df1 <- subset(df, ( # (Transport == "partisan" & Channels == 4 & Parallelism == Concurrencys & Affinity == "true") |
  (Transport == "partisan" & Channels == 4 & Parallelism == 16 & Affinity == "true") |
    (Transport == "disterl"  & Channels == 1))
  & (Latency == "1") & (Size == "8388608" | Size == "524288") & is.element(Concurrency, c(16, 32, 64, 128)))
# Size == "1048576" | 
df1$Concurrency <- factor(df1$Concurrency)
df1$Experiment <- paste(df1$Transport, ifelse(df1$Size == "8388608", "8.0MB", "0.5MB"))
df1$Size <- factor(ifelse(df1$Size == "8388608", "8.0MB", "0.5MB"))

df2 <- aggregate(df1$Time, list(df1$Transport, df1$Concurrency, df1$Size, df1$Experiment), length)
colnames(df2) <- c("Transport", "Concurrency", "Size", "Experiment","Ops")

ggplot(data = df2, aes(x = Concurrency, y = (Ops / 120), fill = Transport, group = Experiment, color = Experiment)) +
  geom_line(aes(linetype=Transport), size=1) + geom_point(size=2, aes(shape=Size)) + ylab("Ops/Second") + ylim(0, 200) +
  theme_grey(base_size = 12) + 
  theme(legend.position = c(0.1, 0.6), legend.background = element_rect(color = "black", fill = "grey90", size = 1, linetype = "solid")) +
  ggtitle("512KB/8MB, 1ms RTT Latency, KVS Throughput")

ggsave("c:\\users\\chris\\github\\unir\\KVS1MSThroughput.pdf")

########################################################################
# KVS 20ms

df <- read.csv("c:\\users\\chris\\GitHub\\unir\\throughput-kvs.csv", header = FALSE)
colnames(df) <- c("App", "Transport", "Concurrency", "Channels", "Monotonic", "Parallelism", "Affinity", "Size", "Num", "Latency", "Time")
df <- transform(df, Time = as.numeric(Time) / 1000)

df1 <- subset(df, ( # (Transport == "partisan" & Channels == 4 & Parallelism == Concurrency & Affinity == "true") |
  (Transport == "partisan" & Channels == 4 & Parallelism == 16 & Affinity == "true") |
    (Transport == "disterl"  & Channels == 1))
  & (Latency == "20") & (Size == "8388608" | Size == "524288") & is.element(Concurrency, c(16, 32, 64, 128)))
# Size == "1048576" | 
df1$Concurrency <- factor(df1$Concurrency)
df1$Experiment <- paste(df1$Transport, ifelse(df1$Size == "8388608", "8.0MB", "0.5MB"))
df1$Size <- factor(ifelse(df1$Size == "8388608", "8.0MB", "0.5MB"))

df2 <- aggregate(df1$Time, list(df1$Transport, df1$Concurrency, df1$Size, df1$Experiment), length)
colnames(df2) <- c("Transport", "Concurrency", "Size", "Experiment","Ops")

ggplot(data = df2, aes(x = Concurrency, y = (Ops / 120), fill = Transport, group = Experiment, color = Experiment)) +
  geom_line(aes(linetype=Transport), size=1) + geom_point(size=2, aes(shape=Size)) + ylab("Ops/Second") + ylim(0, 200) +
  theme_grey(base_size = 12) + 
  theme(legend.position = c(0.1, 0.6), legend.background = element_rect(color = "black", fill = "grey90", size = 1, linetype = "solid")) +
  ggtitle("512KB/8MB, 20ms RTT Latency, KVS Throughput")

ggsave("c:\\users\\chris\\github\\unir\\KVS20MSThroughput.pdf")