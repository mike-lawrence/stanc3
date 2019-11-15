functions {
  matrix K (vector phi, vector[] x, real[] delta, int[] delta_int) {
    matrix[1, 1] covariance;
    return covariance;
  }
}

transformed data {
  int y[1];
  int n_samples[1];

  vector[1] phi;
  vector[1] x[1];
  real delta[1];
  int delta_int[1];
  
  vector[1] theta0;
}

parameters {
  vector[1] phi_v;
  vector[1] theta0_v;
}

model {
  target +=
    laplace_marginal_bernoulli(y, n_samples, K, phi, x, delta, delta_int,
                               theta0, 1e-3, 100);

  // real y = integrate_1d(integrand, 0, 1, x, x_r, x_i);
  // real z = integrate_1d(integrand, 0, 1, x, x_r, x_i, 1e-8);
  // x ~ normal(y + z, 1.0);
}
