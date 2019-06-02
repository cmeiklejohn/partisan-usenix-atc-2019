library(ggplot2)
library(scales)

# Echo 20ms

df <- read.csv("../throughput-echo-1-20ms.csv", header = FALSE)
colnames(df) <- c("App", "Transport", "Concurrency", "Channels", "Monotonic", "Parallelism", "Affinity", "Size", "Num", "Latency", "Time")
df <- transform(df, Time = as.numeric(Time) / 1000)

df1 <- subset(df, ( 
  (Transport == "partisan" & Channels == 4 & Parallelism == 16 & Affinity == "true") |
    (Transport == "disterl"  & Channels == 1)
)
& (Latency == "20") & (Size == "1024" | Size == "8388608" | Size == "524288") & is.element(Concurrency, c(16, 32, 64, 128)))
df1$Transport <- paste("", ifelse(df1$Transport == "partisan", "partisan", "disterl"), sep="")
df1$Concurrency <- factor(df1$Concurrency)
df1$Experiment <- paste(df1$Transport, "@", ifelse(df1$Size == "8388608", "8192KB", ifelse(df1$Size == "524288", "512KB", "1KB")))
df1$Size <- factor(ifelse(df1$Size == "8388608", "8192KB", ifelse(df1$Size == "524288", "512KB", "1KB")))

df2 <- aggregate(df1$Time, list(df1$Transport, df1$Concurrency, df1$Size, df1$Experiment), length)
colnames(df2) <- c("Transport", "Concurrency", "Size", "Experiment","Ops")

for(n in c(2, 3, 4, 5)) {
  df3 <- read.csv(paste("../throughput-echo-", toString(n), "-20ms.csv", sep=""), header = FALSE)
  
  colnames(df3) <- c("App", "Transport", "Concurrency", "Channels", "Monotonic", "Parallelism", "Affinity", "Size", "Num", "Latency", "Time")
  df3 <- transform(df3, Time = as.numeric(Time) / 1000)
  
  df4 <- subset(df3, ( 
    (Transport == "partisan" & Channels == 4 & Parallelism == 16 & Affinity == "true") |
      (Transport == "disterl"  & Channels == 1)
  )
  & (Latency == "20") & (Size == "1024" | Size == "8388608" | Size == "524288") & is.element(Concurrency, c(16, 32, 64, 128)))
  df4$Transport <- paste("", ifelse(df3$Transport == "partisan", "partisan", "disterl"), sep="")
  df4$Concurrency <- factor(df3$Concurrency)
  df4$Experiment <- paste(df3$Transport, "@", ifelse(df3$Size == "8388608", "8192KB", ifelse(df3$Size == "524288", "512KB", "1KB")))
  df4$Size <- factor(ifelse(df3$Size == "8388608", "8192KB", ifelse(df3$Size == "524288", "512KB", "1KB")))
  
  df5 <- aggregate(df4$Time, list(df4$Transport, df4$Concurrency, df4$Size, df4$Experiment), length)
  colnames(df5) <- c("Transport", "Concurrency", "Size", "Experiment","Ops")
  df2 <- rbind(df2, df5)
}

df2$Join <- paste(df2$Experiment, df2$Concurrency)

std = function(x) sd(x)/sqrt(length(x))

mean <- aggregate(Ops ~ Join + Transport + Concurrency + Size + Experiment, df2, function(x) mean(x))
colnames(mean) <- c("Join", "Transport", "Concurrency", "Size", "Experiment", "Mean")

lower <- aggregate(Ops ~ Join, df2, function(x) mean(x) - std(x))
colnames(lower) <- c("Join", "Lower")

upper <- aggregate(Ops ~ Join, df2, function(x) mean(x) + std(x))
colnames(upper) <- c("Join", "Upper")

final <- merge(mean, upper, by="Join")
final <- merge(final, lower, by="Join")

ggplot(data = final, aes(x = Concurrency, y = (Mean / 120), fill = Transport, group = Experiment, color = Experiment)) +
  geom_line(aes(linetype=Transport), size=1) + geom_point(size=2.5, aes(shape=Size)) + ylab("Ops/Second") + ylim(0, 450) +
  geom_errorbar(data = final, aes(width=0.2, ymin=Lower / 120, ymax=Upper / 120)) +
  theme_grey(base_size = 12) + 
  xlab("# of Actors") + 
  ylab("Requests / Second") + 
  theme(# legend.position = c(0.1, 0.6), 
    legend.background = element_rect(color = "black", fill = "grey90", size = 1, linetype = "solid"),
    axis.text=element_text(size=12),
    axis.title=element_text(size=14)) +
  ggtitle("1/512/8192KB, 20ms RTT Latency, Echo Throughput")

ggsave("../Echo20MSThroughput-Final.png", dpi = 400)