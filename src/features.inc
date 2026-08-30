{ Shared language-feature representation and dialect resolution.

  A dialect selects a host-language feature set. DEVICE is a compiland kind,
  not a DialectKind or a feature: DEVICE activation remains owned by the
  typechecker and code generator after they inspect the parsed compiland.

  The two policy fields are represented here so that this state matches the
  Python feature registry. They are deliberately outside the extended
  umbrella and remain off until explicit feature overrides are implemented. }

INTERFACE;
UNIT features;

TYPE
  DialectKind = (DIALECT_VINTAGE, DIALECT_EXTENDED);

  FeatureSet = RECORD
    wide_integers: BOOLEAN;
    wide_reals: BOOLEAN;
    symbolic_enum_io: BOOLEAN;
    string_precision: BOOLEAN;
    readset_set_literal: BOOLEAN;
    tuning_hints: BOOLEAN;
    extended_const_intrinsics: BOOLEAN;
    strict_word_int: BOOLEAN;
    noalias_kernel_params: BOOLEAN;
  END;

PROCEDURE ResolveFeatures(dialect: DialectKind; VAR resolved: FeatureSet);
FUNCTION FeaturesAreExtended(VAR resolved: FeatureSet): BOOLEAN;

END;
