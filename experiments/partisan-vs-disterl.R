library(ggplot2)
library(scales)

df <- read.csv("c:\\users\\chris\\OneDrive\\Desktop\\partisan-perf.csv", header = FALSE)
colnames(df) <- c("App", "Transport", "Concurrency", "Channels", "Monotonic", "Parallelism", "Affinity", "Size", "Num", "Latency", "Time")
df <- transform(df, Time = as.numeric(Time) / 1000 / 1000)

df1 <- subset(df, ( (Transport == "partisan" & Channels == 1 & Parallelism == 1) | 
                      (Transport == "disterl"  & Channels == 1 )) 
              & (Affinity == "false" & Latency == "1"))
df1$Experiment <- paste(df1$Transport,"with",trunc((df1$Size / 1000 / 1000)),"MB payload")
df1$Payload <- trunc((df1$Size / 1000 / 1000))

p <- ggplot(data = df1, aes(x=factor(Concurrency), y=Time, group=Experiment, shape=Experiment, color=Experiment)) +
  geom_line(aes(color=Experiment, linetype=Transport)) +
  geom_point(aes(color=Experiment)) +
  xlab("Concurrent Actors Per Machine") +
  ylab("Elapsed Time for 1,000 Messages [Seconds]") + 
  # ggtitle("Latency: Partisan vs. Distributed Erlang, 1ms RTT") + 
  scale_shape_manual(values=seq(0,15)) +
  scale_x_discrete() +
  theme(legend.justification=c(0,1), legend.position=c(0,1))

p

ggsave("c:\\users\\chris\\github\\unir\\PartisanVsDisterl.pdf")

df <- read.csv("c:\\users\\chris\\OneDrive\\Desktop\\partisan-perf.csv", header = FALSE)
colnames(df) <- c("App", "Transport", "Concurrency", "Channels", "Monotonic", "Parallelism", "Affinity", "Size", "Num", "Latency", "Time")
df <- transform(df, Time = as.numeric(Time) / 1000 / 1000)

df1 <- subset(df, ( (Transport == "partisan" & Channels == 1 & Parallelism == 1) | (Transport == "partisan" & Channels == 1 & Parallelism == Concurrency))
              & (Affinity == "false" & Latency == "1" & Concurrency != "1"))
df1$Experiment <- paste(df1$Transport,"with",trunc((df1$Size / 1000 / 1000)),"MB payload", ifelse(df1$Concurrency != df1$Parallelism, "single", "parallel"))
df1$Parallel <- paste(df1$Parallelism == df1$Concurrency)

p <- ggplot(data = df1, aes(x=factor(Concurrency), y=Time, group=Experiment, shape=Experiment, color=Experiment)) +
  geom_line(aes(color=Experiment, linetype=Parallel)) +
  geom_point(aes(color=Experiment)) +
  xlab("Concurrent Actors Per Machine") +
  ylab("Elapsed Time for 1,000 Messages [Seconds]") +
  # ggtitle("Latency: Partisan vs. Distributed Erlang, 1ms RTT, Parallelism") +
  scale_shape_manual(values=seq(0,15)) +
  scale_x_discrete() +
  theme(legend.justification=c(0,1), legend.position=c(0,1))

p

ggsave("c:\\users\\chris\\github\\unir\\PartisanVsDisterlParallelism.pdf")

df <- read.csv("c:\\users\\chris\\OneDrive\\Desktop\\partisan-perf.csv", header = FALSE)
colnames(df) <- c("App", "Transport", "Concurrency", "Channels", "Monotonic", "Parallelism", "Affinity", "Size", "Num", "Latency", "Time")
df <- transform(df, Time = as.numeric(Time) / 1000 / 1000)

df1 <- subset(df, ( (Transport == "partisan" & Channels == 1 & Parallelism == Concurrency))
              & (Latency == "1" & Concurrency != "1"))
df1$Experiment <- paste(df1$Transport,"with",trunc((df1$Size / 1000 / 1000)),"MB payload", ifelse(df1$Affinity == "true", "affinitized", "random"))
df1$Affinitized <- paste(df1$Affinity == "true")

p <- ggplot(data = df1, aes(x=factor(Concurrency), y=Time, group=Experiment, shape=Experiment, color=Experiment)) +
  geom_line(aes(color=Experiment, linetype=Affinitized)) +
  geom_point(aes(color=Experiment)) +
  xlab("Concurrent Actors Per Machine") +
  ylab("Elapsed Time for 1,000 Messages [Seconds]") +
  # ggtitle("Latency: Partisan vs. Distributed Erlang, 1ms RTT, Affinitized Parallelism") +
  scale_shape_manual(values=seq(0,15)) +
  scale_x_discrete() +
  theme(legend.justification=c(0,1), legend.position=c(0,1))

p

ggsave("c:\\users\\chris\\github\\unir\\PartisanVsDisterlAffinitizedParallelism.pdf")

df <- read.csv("c:\\users\\chris\\OneDrive\\Desktop\\partisan-perf.csv", header = FALSE)
colnames(df) <- c("App", "Transport", "Concurrency", "Channels", "Monotonic", "Parallelism", "Affinity", "Size", "Num", "Latency", "Time")
df <- transform(df, Time = as.numeric(Time) / 1000 / 1000)

df1 <- subset(df, ( (Transport == "partisan" & Channels == 1 & Concurrency == Parallelism & Affinity == "true") |
                      (Transport == "disterl"  & Channels == 1 ) )
              & (Latency == "20"))
df1$Experiment <- paste(df1$Transport,"with",trunc((df1$Size / 1000 / 1000)),"MB payload")
df1$Payload <- trunc((df1$Size / 1000 / 1000))

p <- ggplot(data = df1, aes(x=factor(Concurrency), y=Time, group=Experiment, shape=Experiment, color=Experiment)) +
  geom_line(aes(color=Experiment, linetype=Transport)) +
  geom_point(aes(color=Experiment)) +
  xlab("Concurrent Actors Per Machine") +
  ylab("Elapsed Time for 1,000 Messages [Seconds]") +
  # ggtitle("Latency: Affinitized, Parallel Partisan vs. Distributed Erlang, 20ms RTT") +
  scale_shape_manual(values=seq(0,15)) +
  scale_x_discrete() +
  theme(legend.justification=c(0,1), legend.position=c(0,1))

p

ggsave("c:\\users\\chris\\github\\unir\\PartisanVsDisterlAffinitizedParallelism20msRTT.pdf")