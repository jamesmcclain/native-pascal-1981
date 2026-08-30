(*$INCLUDE:'features.inc'*)
PROGRAM features_unit(input, output);

USES features;

VAR
  vintage_features, extended_features: FeatureSet;

PROCEDURE PrintFeatures(VAR state: FeatureSet);
BEGIN
  WRITELN('wide-integers=', state.wide_integers);
  WRITELN('wide-reals=', state.wide_reals);
  WRITELN('symbolic-enum-io=', state.symbolic_enum_io);
  WRITELN('string-precision=', state.string_precision);
  WRITELN('readset-set-literal=', state.readset_set_literal);
  WRITELN('tuning-hints=', state.tuning_hints);
  WRITELN('extended-const-intrinsics=', state.extended_const_intrinsics);
  WRITELN('strict-word-int=', state.strict_word_int);
  WRITELN('noalias-kernel-params=', state.noalias_kernel_params);
END;

BEGIN
  ResolveFeatures(DIALECT_VINTAGE, vintage_features);
  WRITELN('[vintage]');
  PrintFeatures(vintage_features);
  WRITELN('is-extended=', FeaturesAreExtended(vintage_features));

  ResolveFeatures(DIALECT_EXTENDED, extended_features);
  WRITELN('[extended]');
  PrintFeatures(extended_features);
  WRITELN('is-extended=', FeaturesAreExtended(extended_features));
END.
