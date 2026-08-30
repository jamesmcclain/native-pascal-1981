{ Shared language-feature resolution. See features.inc for the contract. }

(*$INCLUDE:'features.inc'*)
IMPLEMENTATION OF features;

PROCEDURE ResolveFeatures(dialect: DialectKind; VAR resolved: FeatureSet);
VAR
  enable_extended: BOOLEAN;
BEGIN
  enable_extended := dialect = DIALECT_EXTENDED;

  resolved.wide_integers := enable_extended;
  resolved.wide_reals := enable_extended;
  resolved.symbolic_enum_io := enable_extended;
  resolved.string_precision := enable_extended;
  resolved.readset_set_literal := enable_extended;
  resolved.tuning_hints := enable_extended;
  resolved.extended_const_intrinsics := enable_extended;

  { Policy flags do not participate in the extended umbrella. }
  resolved.strict_word_int := FALSE;
  resolved.noalias_kernel_params := FALSE;
END;

FUNCTION FeaturesAreExtended(VAR resolved: FeatureSet): BOOLEAN;
BEGIN
  FeaturesAreExtended := resolved.wide_integers AND
                         resolved.wide_reals AND
                         resolved.symbolic_enum_io AND
                         resolved.string_precision AND
                         resolved.readset_set_literal AND
                         resolved.tuning_hints AND
                         resolved.extended_const_intrinsics;
END;

BEGIN
END.
