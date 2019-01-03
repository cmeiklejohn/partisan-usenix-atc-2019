library(ggplot2)
library(scales)

########################################################################
# Echo 1ms

df <- read.csv("c:\\users\\chris\\GitHub\\unir\\new_experiments\\echo-perf-final.csv", header = FALSE)
colnames(df) <- c("App", "Transport", "Concurrency", "Channels", "Monotonic", "Parallelism", "Affinity", "Size", "Num", "Latency", "Time")
df <- transform(df, Time = as.numeric(Time) / 1000)

df1 <- subset(df, ( # (Transport == "partisan" & Channels == 4 & Parallelism == Concurrency & Affinity == "true") |
                      (Transport == "partisan" & Channels == 4 & Parallelism == 4 & Affinity == "true") |
                      (Transport == "disterl"  & Channels == 1))
              & (Latency == "1") & (Size == "8388608" | Size == "1048576") & is.element(Concurrency, c(16, 32, 64)))
df1$Concurrency <- factor(df1$Concurrency)
df1$Experiment <- paste(df1$Transport, trunc((df1$Size / 1000 / 1000)),"MB")
df1$Size <- factor(trunc((df1$Size / 1000 / 1000)))

df2 <- aggregate(df1$Time, list(df1$Transport, df1$Concurrency, df1$Size, df1$Experiment), length)
colnames(df2) <- c("Transport", "Concurrency", "Size", "Experiment","Ops")

ggplot(data = df2, aes(x = Concurrency, y = (Ops / 120), fill = Transport, group = Experiment, color = Experiment)) +
  geom_line(aes(linetype=Transport), size=1) + geom_point(size=2, aes(shape=Size)) + ylab("Ops/Second") + ylim(0, 300) +
  theme_grey(base_size = 12) + 
  theme(legend.position = c(0.1, 0.6), legend.background = element_rect(color = "black", fill = "grey90", size = 1, linetype = "solid"))

ggsave("c:\\users\\chris\\github\\unir\\new_experiments\\Echo1MSThroughput.pdf")

########################################################################
# Echo 20ms

df <- read.csv("c:\\users\\chris\\GitHub\\unir\\new_experiments\\echo-perf-final.csv", header = FALSE)
colnames(df) <- c("App", "Transport", "Concurrency", "Channels", "Monotonic", "Parallelism", "Affinity", "Size", "Num", "Latency", "Time")
df <- transform(df, Time = as.numeric(Time) / 1000)

df1 <- subset(df, ( # (Transport == "partisan" & Channels == 4 & Parallelism == Concurrency & Affinity == "true") |
  (Transport == "partisan" & Channels == 4 & Parallelism == 4 & Affinity == "true") |
    (Transport == "disterl"  & Channels == 1))
  & (Latency == "20") & (Size == "8388608" | Size == "1048576") & (Concurrency < 120))
df1$Concurrency <- factor(df1$Concurrency)
df1$Experiment <- paste(df1$Transport, trunc((df1$Size / 1000 / 1000)),"MB")
df1$Size <- factor(trunc((df1$Size / 1000 / 1000)))

df2 <- aggregate(df1$Time, list(df1$Transport, df1$Concurrency, df1$Size, df1$Experiment), length)
colnames(df2) <- c("Transport", "Concurrency", "Size", "Experiment","Ops")

ggplot(data = df2, aes(x = Concurrency, y = (Ops / 120), fill = Transport, group = Experiment, color = Experiment)) +
  geom_line(aes(linetype=Transport), size=1) + geom_point(size=2, aes(shape=Size)) + ylab("Ops/Second") + ylim(0, 300)

ggsave("c:\\users\\chris\\github\\unir\\new_experiments\\Echo20MSThroughput.pdf")

########################################################################
# Echo 1ms: Lossy Performance

df <- read.csv("c:\\users\\chris\\GitHub\\unir\\new_experiments\\echo-perf-lossy-final.csv", header = FALSE)
colnames(df) <- c("App", "Transport", "Concurrency", "Channels", "Monotonic", "Parallelism", "Affinity", "Size", "Num", "Latency", "Time")
df <- transform(df, Time = as.numeric(Time) / 1000)

df1 <- subset(df, ( (Transport == "partisan-N" & Channels == 4 & Parallelism == Concurrency & Affinity == "true") |
                      (Transport == "partisan-4" & Channels == 4 & Parallelism == 4 & Affinity == "true")#  |
                    # (Transport == "disterl"  & Channels == 1)
)
& (Latency == "1") & (Size == "8388608" | Size == "1048576") & (Concurrency < 120))
df1$Concurrency <- factor(df1$Concurrency)
df1$Experiment <- paste(df1$Transport, trunc((df1$Size / 1000 / 1000)),"MB")
df1$Size <- factor(trunc((df1$Size / 1000 / 1000)))

df2 <- aggregate(df1$Time, list(df1$Transport, df1$Concurrency, df1$Size, df1$Experiment), length)
colnames(df2) <- c("Transport", "Concurrency", "Size", "Experiment","Ops")

ggplot(data = df2, aes(x = Concurrency, y = (Ops / 120), fill = Transport, group = Experiment, color = Experiment)) +
  geom_line(aes(linetype=Transport), size=1) + geom_point(size=2, aes(shape=Size)) + ylab("Ops/Second")

ggsave("c:\\users\\chris\\github\\unir\\new_experiments\\Echo1MSThroughputLossy.pdf")

########################################################################
# KVS 1ms

df <- read.csv("c:\\users\\chris\\GitHub\\unir\\new_experiments\\fsm-perf-final.csv", header = FALSE)
colnames(df) <- c("App", "Transport", "Concurrency", "Channels", "Monotonic", "Parallelism", "Affinity", "Size", "Num", "Latency", "Time")
df <- transform(df, Time = as.numeric(Time) / 1000)

df1 <- subset(df, ( # (Transport == "partisan" & Channels == 4 & Parallelism == Concurrency & Affinity == "true") |
  (Transport == "partisan" & Channels == 4 & Parallelism == 4 & Affinity == "true") |
    (Transport == "disterl"  & Channels == 1))
  & (Latency == "1") & (Size == "8388608" | Size == "1048576") & (Concurrency < 120))
df1$Concurrency <- factor(df1$Concurrency)
df1$Experiment <- paste(df1$Transport, trunc((df1$Size / 1000 / 1000)),"MB")
df1$Size <- factor(trunc((df1$Size / 1000 / 1000)))

df2 <- aggregate(df1$Time, list(df1$Transport, df1$Concurrency, df1$Size, df1$Experiment), length)
colnames(df2) <- c("Transport", "Concurrency", "Size", "Experiment","Ops")

ggplot(data = df2, aes(x = Concurrency, y = (Ops / 120), fill = Transport, group = Experiment, color = Experiment)) +
  geom_line(aes(linetype=Transport), size=1) + geom_point(size=2, aes(shape=Size)) + ylab("Ops/Second") + ylim(0, 150)

ggsave("c:\\users\\chris\\github\\unir\\new_experiments\\KVS1MSThroughput.pdf")

########################################################################
# KVS 20ms

df <- read.csv("c:\\users\\chris\\GitHub\\unir\\new_experiments\\fsm-perf-final.csv", header = FALSE)
colnames(df) <- c("App", "Transport", "Concurrency", "Channels", "Monotonic", "Parallelism", "Affinity", "Size", "Num", "Latency", "Time")
df <- transform(df, Time = as.numeric(Time) / 1000)

df1 <- subset(df, ( # (Transport == "partisan" & Channels == 4 & Parallelism == Concurrency & Affinity == "true") |
  (Transport == "partisan" & Channels == 4 & Parallelism == 4 & Affinity == "true") |
    (Transport == "disterl"  & Channels == 1))
  & (Latency == "20") & (Size == "8388608" | Size == "1048576") & (Concurrency < 120))
df1$Concurrency <- factor(df1$Concurrency)
df1$Experiment <- paste(df1$Transport, trunc((df1$Size / 1000 / 1000)),"MB")
df1$Size <- factor(trunc((df1$Size / 1000 / 1000)))

df2 <- aggregate(df1$Time, list(df1$Transport, df1$Concurrency, df1$Size, df1$Experiment), length)
colnames(df2) <- c("Transport", "Concurrency", "Size", "Experiment","Ops")

ggplot(data = df2, aes(x = Concurrency, y = (Ops / 120), fill = Transport, group = Experiment, color = Experiment)) +
  geom_line(aes(linetype=Transport), size=1) + geom_point(size=2, aes(shape=Size)) + ylab("Ops/Second") + ylim(0, 150)

ggsave("c:\\users\\chris\\github\\unir\\new_experiments\\KVS20MSThroughput.pdf")




























########################################################################
# KVS 1ms

df <- read.csv("c:\\users\\chris\\GitHub\\unir\\new_experiments\\fsm-perf-final.csv", header = FALSE)
colnames(df) <- c("App", "Transport", "Concurrency", "Channels", "Monotonic", "Parallelism", "Affinity", "Size", "Num", "Latency", "Time")
df <- transform(df, Time = as.numeric(Time) / 1000)

df1 <- subset(df, ( # (Transport == "partisan" & Channels == 4 & Parallelism == Concurrency & Affinity == "true") |
  (Transport == "partisan" & Channels == 4 & Parallelism == 4 & Affinity == "true") |
    (Transport == "disterl"  & Channels == 1))
  & (Latency == "1") & (Size == "8388608" | Size == "1048576"))
df1$Concurrency <- factor(df1$Concurrency)
df1$Experiment <- paste(df1$Transport, trunc((df1$Size / 1000 / 1000)),"MB")
df1$Size <- factor(trunc((df1$Size / 1000 / 1000)))

df2 <- aggregate(df1$Time, list(df1$Transport, df1$Concurrency, df1$Size, df1$Experiment), length)
colnames(df2) <- c("Transport", "Concurrency", "Size", "Experiment","Ops")

ggplot(data = df2, aes(x = Concurrency, y = (Ops / 120), fill = Transport, group = Experiment, color = Experiment)) +
  geom_line(aes(linetype=Transport), size=1) + geom_point(size=2, aes(shape=Size)) + ylab("Ops/Second")

ggsave("c:\\users\\chris\\github\\unir\\new_experiments\\KVS1MSThroughput.pdf")






df <- read.csv("c:\\users\\chris\\GitHub\\unir\\new_experiments\\fsm-perf.csv", header = FALSE)
colnames(df) <- c("App", "Transport", "Concurrency", "Channels", "Monotonic", "Parallelism", "Affinity", "Size", "Num", "Latency", "Time")
df <- transform(df, Time = as.numeric(Time) / 1000)

df1 <- subset(df, ( (Transport == "partisan" & Channels == 4 & Parallelism == Concurrency & Affinity == "true") |
                      (Transport == "disterl"  & Channels == 1))
              & (Latency == "1"))
df1$Concurrency <- factor(df1$Concurrency)
df1$Experiment <- paste(df1$Transport, trunc((df1$Size / 1000 / 1000)),"MB")
df1$Size <- factor(trunc((df1$Size / 1000 / 1000)))

df2 <- aggregate(df1$Time, list(df1$Transport, df1$Concurrency, df1$Size, df1$Experiment), length)
colnames(df2) <- c("Transport", "Concurrency", "Size", "Experiment","Ops")

ggplot(data = df2, aes(x = Concurrency, y = (Ops / 120), fill = Transport, group = Experiment, color = Experiment)) +
  geom_line(aes(linetype=Transport), size=1) + geom_point(size=2, aes(shape=Size)) + ylab("Ops/Second")

ggsave("c:\\users\\chris\\github\\unir\\new_experiments\\FSM1MSThroughput.pdf")

df1 <- subset(df, ( (Transport == "partisan" & Channels == 4 & Parallelism == Concurrency & Affinity == "true") |
                      (Transport == "disterl"  & Channels == 1))
              & (Latency == "20"))
df1$Concurrency <- factor(df1$Concurrency)
df1$Experiment <- paste(df1$Transport, trunc((df1$Size / 1000 / 1000)),"MB")
df1$Size <- factor(trunc((df1$Size / 1000 / 1000)))

df2 <- aggregate(df1$Time, list(df1$Transport, df1$Concurrency, df1$Size, df1$Experiment), length)
colnames(df2) <- c("Transport", "Concurrency", "Size", "Experiment","Ops")

ggplot(data = df2, aes(x = Concurrency, y = (Ops / 120), fill = Transport, group = Experiment, color = Experiment)) +
  geom_line(aes(linetype=Transport), size=1) + geom_point(size=2, aes(shape=Size)) + ylab("Ops/Second")

ggsave("c:\\users\\chris\\github\\unir\\new_experiments\\Echo20MSThroughput.pdf")

df1 <- subset(df, ( (Transport == "partisan" & Channels == 4 & Parallelism == Concurrency & Affinity == "true") |
                      (Transport == "disterl"  & Channels == 1))
              & (Latency == "20"))
df1$Concurrency <- factor(df1$Concurrency)
df1$Experiment <- paste(df1$Transport, trunc((df1$Size / 1000 / 1000)),"MB")
df1$Size <- factor(trunc((df1$Size / 1000 / 1000)))

df2 <- aggregate(df1$Time, list(df1$Transport, df1$Concurrency, df1$Size, df1$Experiment), length)
colnames(df2) <- c("Transport", "Concurrency", "Size", "Experiment","Ops")

ggplot(data = df2, aes(x = Concurrency, y = (Ops / 120), fill = Transport, group = Experiment, color = Experiment)) +
  geom_line(aes(linetype=Transport), size=1) + geom_point(size=2, aes(shape=Size)) + ylab("Ops/Second")

ggsave("c:\\users\\chris\\github\\unir\\new_experiments\\FSM20MSThroughput.pdf")


