#####################################################
# Utility functions
#####################################################

utils::globalVariables(c("a", "x", "y", "X", "X0", "X1", "ipw", "treated"))

`%notin%` <- Negate(`%in%`)

# logical or infix function
`%||%` <- function(a, b) if (!is.null(a)) a else b

get_formula <- function(object, class){

  if(inherits(object, "lm")){
    out <- formula(object)
  } else if(class(object) %in% c("pbart", "wbart")){
    x <- attr(object$varcount.mean, "names")
    out <- as.formula(paste(y, " ~ ", paste(x, collapse= "+")), env = .GlobalEnv)
  } else NULL
}

mframe <- function(formula, data){

  mf <- model.frame(formula, data, na.action = NULL)
  mf[, -1, drop = FALSE]
}

fit <- function(formula, class, family, newdata){

  if(class=="lm"){
    out <- lm(formula, data = newdata)
  } else if (class=="glm"){
    out <- glm(formula, family = family, data = newdata)
  } else{
    X <- as.matrix(mframe(formula, data = newdata))
    Y <- model.frame(formula, data = newdata, na.action = NULL)[[1]]

    sink(tempfile()); on.exit(sink(), add = TRUE)
    if (class=="wbart"){
      out <- wbart(x.train = X, y.train = Y)
    } else if(class=="pbart")
    {
      out <- pbart(x.train = X, y.train = Y)
    } else out <- NULL
  }
  out
}

impute <- function(model, mf){

  mf1_untreated <- mf[!treated, , drop = FALSE]; mf1_untreated[, a] <- 1
  mf0_treated <- mf[treated, , drop = FALSE]; mf0_treated[, a] <- 0

  sink(tempfile()); on.exit(sink(), add = TRUE)
  imp_y1_untreated <- pred(model, mf1_untreated)
  imp_y0_treated <- pred(model, mf0_treated)

  list(imp_y1_untreated, imp_y0_treated)
}

pure <- function(imp, class, family){

  imp_y1_untreated <- imp[[1]]
  imp_y0_treated <- imp[[2]]

  form_imp_y1 <- as.formula(paste("imp_y1_untreated", " ~ ", paste(x, collapse= "+")))
  form_imp_y0 <- as.formula(paste("imp_y0_treated", " ~ ", paste(x, collapse= "+")))

  if(class == "lm"){

    model_imp_y1 <- lm(form_imp_y1, data = X0)
    model_imp_y0 <- lm(form_imp_y0, data = X1)

    imp_y1 <- pred(model_imp_y1, X)
    imp_y0 <- pred(model_imp_y0, X)

  } else if(class == "glm"){

    if(family[["family"]] == "binomial") family <- quasibinomial()
    if(family[["family"]] == "poisson") family <- quasipoisson()

    model_imp_y1 <- glm(form_imp_y1, family = family, data = X0)
    model_imp_y0 <- glm(form_imp_y0, family = family, data = X1)

    imp_y1 <- pred(model_imp_y1, X)
    imp_y0 <- pred(model_imp_y0, X)

  } else if(class %in% c("pbart", "wbart")){

    sink(tempfile())
    model_imp_y1 <- wbart(x.train = as.matrix(X0),
                          y.train = imp_y1_untreated,
                          x.test = as.matrix(X))
    model_imp_y0 <- wbart(x.train = as.matrix(X1),
                          y.train = imp_y0_treated,
                          x.test = as.matrix(X))
    sink()
    imp_y1 <- model_imp_y1[["yhat.test.mean"]]
    imp_y0 <- model_imp_y0[["yhat.test.mean"]]

  } else stop("'class' must belong to 'lm', 'glm', 'pbart', or 'wbart'")

  imp_Ey1 <- mean(imp_y1, na.rm = TRUE)
  imp_Ey0 <- mean(imp_y0, na.rm = TRUE)

  c(imp_Ey1, imp_Ey0)
}

hybrid <- function(imp){

  imp_y1_untreated <- imp[[1]]
  imp_y0_treated <- imp[[2]]

  imp_Ey1 <- sum(imp_y1_untreated * ipw[!treated], na.rm = TRUE)/sum(ipw[!treated], na.rm = TRUE)
  imp_Ey0 <- sum(imp_y0_treated * ipw[treated], na.rm = TRUE)/sum(ipw[treated], na.rm = TRUE)

  c(imp_Ey1, imp_Ey0)
}
