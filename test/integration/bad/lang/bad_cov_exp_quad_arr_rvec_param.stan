data {
  int K;
  int N_1;
  int N_2;
}
parameters {
  real d_sigma;
  real d_len;
  array[N_1] row_vector[K] d_vec_1;
  array[N_2] real d_arr_1; // bad mixed Eigen vector types
}
transformed parameters {
  matrix[N_2, N_1] transformed_param_matrix;

  transformed_param_matrix = cov_exp_quad(d_arr_2, d_vec_1, d_sigma, d_len);
}
parameters {
  real y;
}
model {
  y ~ normal(0,1);
}
