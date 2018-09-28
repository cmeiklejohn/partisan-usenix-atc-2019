library(ggplot2)
library(scales)

df <- read.csv("c:\\users\\chris\\GitHub\\unir\\new_experiments\\partisan-perf.csv", header = FALSE)
colnames(df) <- c("App", "Transport", "Concurrency", "Channels", "Monotonic", "Parallelism", "Affinity", "Size", "Num", "Latency", "Time")
df <- transform(df, Time = as.numeric(Time) / 1000)
df$Index <- rownames(df)

df1 <- subset(df, ( (Transport == "partisan" & Channels == 1 & Parallelism == 1 & Affinity == "false"))
                & (Size == 1048576 & Latency == "1"))

ggplot(data = df1, aes(x = Index, y = Time)) + geom_line()




# df <- read.csv("c:\\users\\chris\\GitHub\\unir\\new_experiments\\partisan-perf.csv", header = FALSE)
# colnames(df) <- c("App", "Transport", "Concurrency", "Channels", "Monotonic", "Parallelism", "Affinity", "Size", "Num", "Latency", "Time")
# df <- transform(df, Time = as.numeric(Time) / 1000)
# 
# df1 <- subset(df, ( (Transport == "partisan" & Channels == 1 & Parallelism == 1 & Affinity == "false") | 
#                     (Transport == "disterl"  & Channels == 1)) 
#                 & (Size == 1048576 & Latency == "1"))
# df1$Concurrency <- factor(df1$Concurrency)
# 
# ggplot(data = df1, aes(x = Concurrency, y = Time, fill = Transport)) +
#   geom_boxplot() + ylab("Milliseconds")
# 
# ggsave("c:\\users\\chris\\github\\unir\\new_experiments\\Baseline.pdf")
# 
# df1 <- subset(df, ( 
#   (Transport == "partisan" & Channels == 1 & Parallelism == 1 & Affinity == "false") | 
#   (Transport == "partisan" & Channels == 1 & Parallelism == Concurrency & Affinity == "false") )
#               & (Size == 1048576 & Latency == "1" & Concurrency != 1))
# df1$Concurrency <- factor(df1$Concurrency)
# df1$Experiment <- paste(df1$Transport,ifelse(df1$Parallelism == df1$Concurrency, "parallel", " "))
# 
# ggplot(data = df1, aes(x = Concurrency, y = Time, fill = Experiment)) +
#   geom_boxplot() + ylab("Milliseconds")
# 
# ggsave("c:\\users\\chris\\github\\unir\\new_experiments\\PartisanParallel.pdf")
# 
# df1 <- subset(df, ( 
#   (Transport == "partisan" & Channels == 1 & Parallelism == Concurrency & Affinity == "false") |
#   (Transport == "partisan" & Channels == 1 & Parallelism == Concurrency & Affinity == "true") )
#   & (Size == 1048576 & Latency == "1" & Concurrency != 1))
# df1$Concurrency <- factor(df1$Concurrency)
# df1$Experiment <- paste(df1$Transport,ifelse(df1$Affinity == "true", "affinitized", " "))
# 
# ggplot(data = df1, aes(x = Concurrency, y = Time, fill = Experiment)) +
#   geom_boxplot() + ylab("Milliseconds")
# 
# ggsave("c:\\users\\chris\\github\\unir\\new_experiments\\PartisanParallelAffinity.pdf")
# 
# df1 <- subset(df, ( 
#   (Transport == "disterl" & Channels == 1 & Parallelism == 1 & Affinity == "false") |
#     (Transport == "partisan" & Channels == 1 & Parallelism == Concurrency & Affinity == "true") )
#   & (Size == 1048576 & Latency == "20" & Concurrency != 1))
# df1$Concurrency <- factor(df1$Concurrency)
# df1$Experiment <- paste(df1$Transport,ifelse(df1$Affinity == "true", "affinitized", " "))
# 
# ggplot(data = df1, aes(x = Concurrency, y = Time, fill = Experiment)) +
#   geom_boxplot() + ylab("Milliseconds")
# 
# ggsave("c:\\users\\chris\\github\\unir\\new_experiments\\PartisanDisterlHighLatency1MB.pdf")
# 
# df1 <- subset(df, ( 
#   (Transport == "disterl" & Channels == 1 & Parallelism == 1 & Affinity == "false") |
#     (Transport == "partisan" & Channels == 1 & Parallelism == Concurrency & Affinity == "true") )
#   & (Size == 8388608 & Latency == "20" & Concurrency != 1))
# df1$Concurrency <- factor(df1$Concurrency)
# df1$Experiment <- paste(df1$Transport,ifelse(df1$Affinity == "true", "affinitized", " "))
# 
# ggplot(data = df1, aes(x = Concurrency, y = Time, fill = Experiment)) +
#   geom_boxplot() + ylab("Milliseconds")
# 
# ggsave("c:\\users\\chris\\github\\unir\\new_experiments\\PartisanDisterlHighLatency8MB.pdf")
# 
