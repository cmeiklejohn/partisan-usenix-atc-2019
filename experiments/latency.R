library(ggplot2)
library(scales)

df <- read.csv("c:\\users\\chris\\GitHub\\unir\\latency.csv", header = FALSE)
colnames(df) <- c("App", "Transport", "Concurrency", "Channels", "Monotonic", "Parallelism", "Affinity", "Size", "Num", "Latency", "Time")
df <- transform(df, Time = as.numeric(Time) / 1000 / 1000)

df1 <- subset(df, ( (Transport == "partisan" & Channels == 4) | 
                    (Transport == "disterl"  & Channels == 1)) 
              & (Size == 1048576 & Latency >= 30))

p <- ggplot(data = df1, aes(x=Latency, y=Time, group=Transport, shape=Transport, color=Transport)) +
  geom_line(aes(color=Transport)) +
  geom_point(aes(color=Transport)) +
  xlab("Latency, RTT [Seconds]") +
  ylab("Elapsed Time for 1,000 Messages [Seconds]") +
  theme(legend.justification=c(0,1), legend.position=c(0,1))
  # ggtitle("KVS, 10:1 read/write")

p

ggsave("c:\\users\\chris\\github\\unir\\KVS-10-1-Latency.pdf")
