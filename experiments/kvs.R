require(gridExtra)
library(ggplot2)
library(scales)

df <- read.csv("c:\\users\\chris\\Github\\unir\\results-kvs-50-50-20ms.csv", header = FALSE)
colnames(df) <- c("App", "Transport", "Concurrency", "Channels", "Monotonic", "Parallelism", "Affinity", "Size", "Num", "Latency", "Time")
df <- transform(df, Time = as.numeric(Time) / 1000 / 1000)

df1 <- subset(df, ( (Transport == "partisan" & Channels == 4 & Concurrency == Parallelism & Affinity == "true" & Monotonic == "true") | 
                      (Transport == "disterl"  & Channels == 1 ) ) & Latency == "20")
df1$Experiment <- paste(df1$Transport,"with",trunc((df1$Size / 1000 / 1000)),"MB payload")
df1$Payload <- trunc((df1$Size / 1000 / 1000))

p1 <- ggplot(data = df1, aes(x=factor(Concurrency), y=Time, group=Experiment, shape=Experiment, color=Experiment)) +
  geom_line(aes(color=Experiment, linetype=Transport)) +
  geom_point(aes(color=Experiment)) +
  xlab("Concurrent Actors Per Machine") +
  ylab("Elapsed Time for 1,000 Messages [Seconds]") + 
  # ggtitle("Echo Service: Fully Optimized Partisan vs. Distributed Erlang, 1ms RTT") + 
  scale_shape_manual(values=seq(0,15)) +
  scale_x_discrete() +
  theme(legend.justification=c(0,1), legend.position=c(0,1))

p1

ggsave("c:\\users\\chris\\github\\unir\\KVS-50-50-20msRTT.pdf")

require(gridExtra)
library(ggplot2)
library(scales)

df <- read.csv("c:\\users\\chris\\Github\\unir\\results-10-1-kvs-perf-1-ms-RTT.csv", header = FALSE)
colnames(df) <- c("App", "Transport", "Concurrency", "Channels", "Monotonic", "Parallelism", "Affinity", "Size", "Num", "Latency", "Time")
df <- transform(df, Time = as.numeric(Time) / 1000 / 1000)

df1 <- subset(df, ( (Transport == "partisan" & Channels == 4 & Concurrency == Parallelism & Affinity == "true" & Monotonic == "true") | 
                      (Transport == "disterl"  & Channels == 1 ) ) & Latency == "1")
df1$Experiment <- paste(df1$Transport,"with",trunc((df1$Size / 1000 / 1000)),"MB payload")
df1$Payload <- trunc((df1$Size / 1000 / 1000))

p1 <- ggplot(data = df1, aes(x=factor(Concurrency), y=Time, group=Experiment, shape=Experiment, color=Experiment)) +
  geom_line(aes(color=Experiment, linetype=Transport)) +
  geom_point(aes(color=Experiment)) +
  xlab("Concurrent Actors Per Machine") +
  ylab("Elapsed Time for 1,000 Messages [Seconds]") + 
  # ggtitle("Echo Service: Fully Optimized Partisan vs. Distributed Erlang, 1ms RTT") + 
  scale_shape_manual(values=seq(0,15)) +
  scale_x_discrete() +
  theme(legend.justification=c(0,1), legend.position=c(0,1))

p1

ggsave("c:\\users\\chris\\github\\unir\\KVS-10-1-1msRTT.pdf")

