data {
  (int<lower=0, upper=1>, (array[2] int, array[2] int)) ds;
}
parameters {
  (real<lower=0>, real<lower=0>) ps;
}
model {
  ds.1 ~ bernoulli(ps.1);

  target += ps.2 + ds.2.1[1] + ds.2.2[2];
}
