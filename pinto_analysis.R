# Load packages and data
library(tidyverse)
library(afex)
library(emmeans)
library(stats)
library(reshape2)
library(pastecs)
library(MOTE)

set.seed(21)

data <- read_csv("shakey_noshakey_data.csv")
head(data)

# Prepare data --------------------------------------------------------------------

# Create response variable as per the original study

# Pivot data wider 
wide_data <- data %>%
  select(id, condition, ft_height) %>%
  pivot_wider(names_from = condition, 
              values_from = ft_height,
              values_fn = function(x) mean(x, na.rm = TRUE)) %>% # compute the mean of the ten trials for each condition
  rowwise %>%
  mutate(percent_diff = ((shakey-noshakey)/noshakey)*100) %>% # Create new variable for percentage difference between shakey and no shakey condition
  mutate(response = case_when(percent_diff > 0.1 ~ 'Responder', # Create new variable for responder vs non-responder
                              percent_diff < 0.1 ~ 'Non-responder'))

# add response variable to the long data set

data$response <- rep(wide_data$response, each=20, length.out=1120)

# Assumptions ----------------------------------------------------------------------------

# Descriptives ------------

summary_data <- data %>%
  group_by(condition) %>%
  summarise(mean = mean(ft_height),
            sd = sd(ft_height))
summary_data

# Plots ---------------------------------------------------------------------------

### Histogram 

# Prepare data
hist_dat <- data %>%
  select(ft_height)

hist_dat$id <- 1:nrow(hist_dat)
hist_dat <- melt(hist_dat, id.vars = "id")

# Plot histogram
hist <- ggplot(data = hist_dat, aes(x = value, fill = variable)) +
  geom_histogram(color = "black", fill = "white",
                 bins = 15) +
  facet_wrap( ~ variable) +
  scale_x_continuous(name = "Jump Height")
hist

### Q-Q plots 

ggplot(data, aes(sample = ft_height)) +
  geom_qq() +
  geom_qq_line() +
  scale_x_continuous(name = "Observed Value") +
  scale_y_continuous(name = "Expected Normal")


### Boxplot 

ggplot(data, aes(x = condition, y = ft_height)) +
  geom_violin(trim = FALSE) +
  geom_boxplot(width = .2)

# ANOVA omnibus test ----------------------------------------------------------------------------

data_afx <- afex::aov_4(
  ft_height ~ response + (trial * condition | id),
  data = data,
  anova_table = list(correction = "GG", es = "pes")
) # using Greenhouse Geisser sphercity correction and partial eta squared
data_afx

summary(data_afx)

## Assumption checking ---------

### Normality test -------

shapiro.test(data_afx$lm$residuals) # residuals are not normally distributed

data %>% 
  group_by(condition) %>% 
  rstatix::shapiro_test(ft_height) # individual groups are not normally distributed

data %>% 
  group_by(trial) %>% 
  rstatix::shapiro_test(ft_height) # individual groups are not normally distributed

### Outliers check -------

data %>%
  group_by(condition) %>%
  rstatix::identify_outliers(ft_height)

data %>%
  group_by(trial) %>%
  rstatix::identify_outliers(ft_height)

### Homeogeneity test -------

performance::check_homogeneity(data_afx)

## Post hoc contrasts ----------------------------------------------------------------------------

data_emm_condition <-
  emmeans::emmeans(data_afx, ~ condition, model = "multivariate")
data_emm_condition

data_emm_trial <-
  emmeans::emmeans(data_afx, ~ trial, model = "multivariate")
data_emm_trial

posthocresults <- pairs(data_emm_condition, adjust = "bon") %>%
  broom::tidy(conf.int = T)
posthocresults

# Original study values -------------

ori_study <- data.frame(
  ori_pval = 0.016,
  ori_N = 11,
  ori_df1 = 1,
  ori_df2 = 10,
  reported_es = 0.496)

# Calculate the F-value from the original study using the reported p-value

pval = ori_study$ori_pval
quantile = 1 - pval

ori_Fval <- qf(quantile, df1=ori_study$ori_df1, df2=ori_study$ori_df2)
ori_Fval

# Confirming the reported effect size

#Calculating es and its CI
#ANOVA - Calculating partial eta squared using F statistic and df
#dfm = degrees of freedom for the model/IV/between
#dfe = degrees of freedom for the error/residual/within

calculated_ori_es <- eta.F(dfm=ori_study$ori_df1, dfe=ori_study$ori_df2, Fvalue=ori_Fval, a = 0.05)
calculated_ori_es

# This calculation doesn't match the reported pes of 0.496

# Replication z-test using reported value -----
# main effect of condition

pes_rep = data_afx$anova_table$pes[4]
df_rep = data_afx$anova_table$`den Df`[4]
pes_ori = 0.496
df_ori = 10

rho_ori = 2 * sqrt(pes_ori) - 1
rho_rep = 2 * sqrt(pes_rep) - 1

rep_test = TOSTER::compare_cor(r1 = rho_ori,
                               df1 = df_ori,
                               r2 = rho_rep,
                               df2 = df_rep,
                               alternative = "greater")
rep_test


# Z-test using the calculated original effect size ------

rho_ori_calc = 2 * sqrt(calculated_ori_es$eta) - 1

rep_test = TOSTER::compare_cor(r1 = rho_ori_calc,
                               df1 = df_ori,
                               r2 = rho_rep,
                               df2 = df_rep,
                               alternative = "greater")
rep_test

# Calculating CI for pes

pes_rep <- eta.F(
  dfm = data_afx$anova_table$`num Df`[4],
  dfe = data_afx$anova_table$`den Df`[4],
  Fvalue = data_afx$anova_table$F[4],
  a = 0.05) %>%
  as.data.frame() %>%
  select(eta, etalow, etahigh) %>%
  mutate(study_id = c("Replication study")) # add identifier
pes_rep
