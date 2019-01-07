library(ggplot2)
library(scales)

df <- read.csv("c:\\users\\chris\\GitHub\\unir\\microbenchmarks.csv", header = FALSE)
colnames(df) <- c("App", "Transport", "Concurrency", "Channels", "Monotonic", "Parallelism", "Affinity", "Size", "Num", "Latency", "Time")
df <- transform(df, Time = round(as.numeric(Time) / 1000, digits = 0))

df1 <- subset(df, (
  (Transport == "disterl" & Channels == 1 & Parallelism == 1 & Affinity == "false") |
 #   (Transport == "partisan" & Channels == 1 & Parallelism == Concurrency & Affinity == "false") |
  #  (Transport == "partisan" & Channels == 1 & Parallelism == 1 & Affinity == "false") |
    (Transport == "partisan" & Channels == 4 & Parallelism == 16 & Affinity == "true") # |
  #  (Transport == "partisan" & Channels == 4 & Parallelism == Concurrency & Affinity == "true")
  )
  & (Size == 524288 & Latency == "1" & is.element(Concurrency, c(16, 32, 64, 128))))
df1$Concurrency <- factor(df1$Concurrency)
df1$Experiment <- paste("",
                        ifelse(df1$Affinity == "true" & df1$Transport == "partisan" & df1$Parallelism == 16, "prototype parallel affinitized (N = 16)",
                               ifelse(df1$Affinity == "true" & df1$Transport == "partisan" & df1$Concurrency == df1$Parallelism, "parallel affinitized (N = N)", 
                                      ifelse(df1$Affinity == "false" & df1$Transport == "partisan" & df1$Parallelism == 1, "",
                                             ifelse(df1$Affinity == "false" & df1$Transport == "partisan" & df1$Parallelism == df1$Concurrency, "parallel (N = N)",
                                                    "baseline")))))

ggplot(data = df1, aes(x = Concurrency, y = Time, fill = Experiment)) +
  geom_boxplot() + 
  theme_grey(base_size = 12) + 
  ylab("Milliseconds (log2)") + 
  xlab("# of Actors") +
  scale_y_continuous(trans='log2') + 
  ggtitle("512KB Payload, 1ms RTT Latency") +
  theme(legend.position = c(0.2, 0.9), 
        legend.background = element_rect(color = "black", fill = "grey90", size = 1, linetype = "solid"),
        axis.text=element_text(size=14),
        axis.title=element_text(size=16))

ggsave("c:\\users\\chris\\github\\unir\\Microbenchmarks.png", dpi=400)
