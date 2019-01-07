library(ggplot2)
library(scales)

df <- read.csv("c:\\users\\chris\\GitHub\\unir\\microbenchmarks-queueoverhead.csv", header = FALSE)
colnames(df) <- c("App", "Transport", "Concurrency", "Channels", "Monotonic", "Parallelism", "Affinity", "Size", "Num", "Latency", "Time")
df <- transform(df, Time = round(as.numeric(Time) / 1000), digits = 0)

df1 <- subset(df, (
  # (Transport == "disterl" & Channels == 1 & Parallelism == 1 & Affinity == "false") |
  #   (Transport == "partisan" & Channels == 1 & Parallelism == Concurrency & Affinity == "false") |
  #  (Transport == "partisan" & Channels == 1 & Parallelism == 1 & Affinity == "false") |
    (Transport == "partisan" & Channels == 4 & Affinity == "true")
  # (Transport == "partisan" & Channels == 4 & Parallelism == Concurrency & Affinity == "true") 
)
& (Size == 524288 & Latency == "1" & is.element(Concurrency, c(128))))
df1$Concurrency <- factor(df1$Concurrency)
df1$Experiment <- paste("prototype parallel affinitized")

ggplot(data = df1, aes(x = factor(Parallelism), y = Time, fill = Experiment)) +
  geom_boxplot() + 
  theme_grey(base_size = 12) + 
  ylab("Milliseconds") + 
  xlab("Parallelism") +
  ggtitle("512KB Payload, 1ms RTT Latency, 128 Actors") +
  theme(legend.position = c(0.2, 0.9), 
        legend.background = element_rect(color = "black", fill = "grey90", size = 1, linetype = "solid"),
        axis.text=element_text(size=14),
        axis.title=element_text(size=16))

ggsave("c:\\users\\chris\\github\\unir\\Microbenchmarks-QueueOverhead.png", dpi = 400)
