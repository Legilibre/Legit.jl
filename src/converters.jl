# Legit.jl -- Convert French law in LEGI format to Git & Markdown
# By: Emmanuel Raviart <emmanuel.raviart@data.gouv.fr>
#
# Copyright (C) 2015 Etalab
# https://github.com/etalab/Legit.jl
#
# The GitLegistique.jl package is licensed under the MIT "Expat" License.


empty_element_to_nothing = @compat pipe(
  test_isa(Dict),
  struct(
    Dict{String, Any}(
      "^tail" => pipe(
        test_isa(String),
        strip,
        test_nothing,
      ),
      "^text" => pipe(
        test_isa(String),
        strip,
        test_nothing,
      ),
    ),
    drop_nothing = true,
  ),
  empty_to_nothing,
  test_nothing,
)


extract_singleton = pipe(
  test_isa(Array),
  test(values -> length(values) == 1; error = N_("Array must be a singleton.")),
  extract_when_singleton,
)


validate_cid = pipe(
  test_isa(String),
  empty_to_nothing,
  test(cid -> ismatch(r"^(JORF|LEGI)(SCTA|TEXT)\d{12}$", cid); error = N_("Invalid CID.")),
)


validate_date = pipe(
  test_isa(String),
  empty_to_nothing,
  condition(
    test_equal("2999-01-01"),
    from_value(nothing),
    iso8601_string_to_date,
  ),
)


validate_etat = pipe(
  test_isa(String),
  empty_to_nothing,
  test_in(["ABROGE", "MODIFIE", "VIGUEUR"]),
)


validate_id = pipe(
  test_isa(String),
  empty_to_nothing,
  test(id -> ismatch(r"^(JORF|LEGI)(ARTI|SCTA|TEXT)\d{12}$", id); error = N_("Invalid ID.")),
)


validate_ministere = pipe(
  test_isa(String),
  empty_to_nothing,
  # TODO?
)


validate_nature = pipe(
  test_isa(String),
  empty_to_nothing,
  test_in(["ARRETE", "Article", "CODE", "DECRET", "LOI", "ORDONNANCE"]),
)


validate_nor = pipe(
  test_isa(String),
  empty_to_nothing,
  # TODO?
)


validate_num = pipe(
  test_isa(String),
  empty_to_nothing,
  # TODO?
)


validate_origine = pipe(
  test_isa(String),
  test_in(["JORF", "LEGI"]),
)


validate_url = pipe(
  test_isa(String),
  empty_to_nothing,
  test(url -> ismatch(r"^[\dA-Za-z/]+\.xml$", url); error = N_("Invalid URL."))
)


element_to_contenu = test_isa(XMLElement)


element_to_text = @compat pipe(
  test_isa(Dict),
  struct(
    Dict{String, Any}(
      "^tail" => pipe(
        test_isa(String),
        strip,
        test_nothing,
      ),
      "^text" => pipe(
        test_isa(String),
        strip,
      ),
    ),
    drop_nothing = true,
  ),
  call(element -> get(element, "^text", nothing)),
)


element_singleton_to_text = pipe(
  extract_singleton,
  element_to_text,
)


elements_array_to_liens_articles = @compat pipe(
  test_isa(Array),
  uniform_sequence(
    pipe(
      test_isa(Dict),
      struct(
        Dict{String, Any}(
          "^tail" => pipe(
            test_isa(String),
            strip,
            test_nothing,
          ),
          "^text" => pipe(
            test_isa(String),
            strip,
            test_nothing,
          ),
          "@debut" => validate_date,
          "@etat" => validate_etat,
          "@fin" => validate_date,
          "@id" => pipe(
            validate_id,
            require,
          ),
          "@num" => pipe(
            validate_num,
            require,
          ),
          "@origine" => pipe(
            validate_origine,
            require,
          ),
        ),
        drop_nothing = true,
      ),
      require,
    ),
  ),
)


function element_singleton_to_tm()
  # This converter is defined as a function, because it is recursive.
  return @compat pipe(
    extract_singleton,
    test_isa(Dict),
    struct(
      Dict{String, Any}(
        "^tail" => pipe(
          test_isa(String),
          strip,
          test_nothing,
        ),
        "^text" => pipe(
          test_isa(String),
          strip,
          test_nothing,
        ),
        "TITRE_TM" => pipe(
          extract_singleton,
          test_isa(Dict),
          struct(
            Dict{String, Any}(
              "^tail" => pipe(
                test_isa(String),
                strip,
                test_nothing,
              ),
              "^text" => pipe(
                test_isa(String),
                strip,
                require,
              ),
              "@debut" => pipe(
                validate_date,
                require,
              ),
              "@fin" => validate_date,
              "@id" => pipe(
                validate_id,
                require,
              ),
            ),
            drop_nothing = true,
          ),
          require,
        ),
        "TM" => convertible::Convertible -> element_singleton_to_tm()(convertible),  # Defer evaluation.
      ),
      drop_nothing = true,
    ),
  )
end


element_singleton_to_contexte = @compat pipe(
  extract_singleton,
  test_isa(Dict),
  struct(
    Dict{String, Any}(
      "^tail" => pipe(
        test_isa(String),
        strip,
        test_nothing,
      ),
      "^text" => pipe(
        test_isa(String),
        strip,
        test_nothing,
      ),
      "TEXTE" => pipe(
        extract_singleton,
        test_isa(Dict),
        struct(
          Dict{String, Any}(
            "^tail" => pipe(
              test_isa(String),
              strip,
              test_nothing,
            ),
            "^text" => pipe(
              test_isa(String),
              strip,
              test_nothing,
            ),
            "@autorite" => pipe(
              test_isa(String),
              empty_to_nothing,
              test_nothing,
            ),
            "@cid" => pipe(
              validate_cid,
              require,
            ),
            "@date_publi" => pipe(
              validate_date,
              require,
            ),
            "@date_signature" => pipe(
              validate_date,
              require,
            ),
            "@ministere" => validate_ministere,
            "@nature" => pipe(
              validate_nature,
              require,
            ),
            "@nor" => validate_nor,
            "@num" => pipe(
              validate_num,
              require,
            ),
            "TITRE_TXT" => pipe(
              test_isa(Array),
              uniform_sequence(
                pipe(
                  test_isa(Dict),
                  struct(
                    Dict{String, Any}(
                      "^tail" => pipe(
                        test_isa(String),
                        strip,
                        test_nothing,
                      ),
                      "^text" => pipe(
                        test_isa(String),
                        strip,
                        require,
                      ),
                      "@c_titre_court" => pipe(
                        test_isa(String),
                        empty_to_nothing,
                        require,
                      ),
                      "@debut" => validate_date,
                      "@fin" => validate_date,
                      "@id_txt" => pipe(
                        validate_id,
                        require,
                      ),
                    ),
                    drop_nothing = true,
                  ),
                  require,
                ),
              ),
              require,
            ),
            "TM" => element_singleton_to_tm(),
          ),
          drop_nothing = true,
        ),
        require,
      ),
    ),
    drop_nothing = true,
  ),
)


element_singleton_to_liens = @compat pipe(
  extract_singleton,
  test_isa(Dict),
  struct(
    Dict{String, Any}(
      "^tail" => pipe(
        test_isa(String),
        strip,
        test_nothing,
      ),
      "^text" => pipe(
        test_isa(String),
        strip,
        test_nothing,
      ),
      "LIEN" => pipe(
        test_isa(Array),
        uniform_sequence(
          pipe(
            test_isa(Dict),
            struct(
              Dict{String, Any}(
                "^tail" => pipe(
                  test_isa(String),
                  strip,
                  test_nothing,
                ),
                "^text" => pipe(
                  test_isa(String),
                  call(text -> join(split(text), " ")),
                  empty_to_nothing,
                  require,
                ),
                "@cidtexte" => validate_cid,
                "@datesignatexte" => validate_date,
                "@id" => validate_id,
                "@naturetexte" => validate_nature,
                "@nortexte" => validate_nor,
                "@num" => validate_num,
                "@numtexte" => validate_num,
                "@sens" => pipe(
                  test_isa(String),
                  empty_to_nothing,
                  test_in(["cible", "source"]),
                  require,
                ),
                "@typelien" => pipe(
                  test_isa(String),
                  empty_to_nothing,
                  test_in(["ABROGATION", "ABROGE", "CITATION", "CONCORDANCE", "CONCORDE", "CREATION", "CREE",
                    "MODIFICATION", "MODIFIE", "SPEC_APPLI", "TXT_SOURCE"]),
                  require,
                ),
              ),
              drop_nothing = true,
            ),
            require,
          ),
        ),
      ),
    ),
    drop_nothing = true,
  ),
)


element_singleton_to_meta_commun = @compat pipe(
  extract_singleton,
  test_isa(Dict),
  struct(
    Dict{String, Any}(
      "^tail" => pipe(
        test_isa(String),
        strip,
        test_nothing,
      ),
      "^text" => pipe(
        test_isa(String),
        strip,
        test_nothing,
      ),
      "ANCIEN_ID" => element_singleton_to_text,  # TODO?
      "ID" => pipe(
        element_singleton_to_text,
        validate_id,
        require,
      ),
      "NATURE" => pipe(
        element_singleton_to_text,
        validate_nature,
        require,
      ),
      "ORIGINE" => pipe(
        element_singleton_to_text,
        validate_origine,
        require,
      ),
      "URL" => pipe(
        element_singleton_to_text,
        validate_url,
        require,
      ),
    ),
    drop_nothing = true,
  ),
)


element_singleton_to_meta_texte_chronicle = @compat pipe(
  extract_singleton,
  test_isa(Dict),
  struct(
    Dict{String, Any}(
      "^tail" => pipe(
        test_isa(String),
        strip,
        test_nothing,
      ),
      "^text" => pipe(
        test_isa(String),
        strip,
        test_nothing,
      ),
      "CID" => pipe(
        element_singleton_to_text,
        validate_cid,
        require,
      ),
      "DATE_PUBLI" => pipe(
        element_singleton_to_text,
        validate_date,
      ),
      "DATE_TEXTE" => pipe(
        element_singleton_to_text,
        validate_date,
        require,
      ),
      "DERNIERE_MODIFICATION" => pipe(
        element_singleton_to_text,
        validate_date,
        require,
      ),
      "NOR" => pipe(
        element_singleton_to_text,
        validate_nor,
      ),
      "NUM" => pipe(
        element_singleton_to_text,
        validate_num,
        require,
      ),
      "NUM_SEQUENCE" => pipe(
        element_singleton_to_text,
        input_to_int,
        test_greater_or_equal(0),  # 0 means nothing.
        require,
      ),
      "ORIGINE_PUBLI" => pipe(
        element_singleton_to_text,
        empty_to_nothing,
      ),
      "PAGE_DEB_PUBLI" => pipe(
        element_singleton_to_text,
        input_to_int,
        test_greater_or_equal(0),  # 0 means nothing.
        require,
      ),
      "PAGE_FIN_PUBLI" => pipe(
        element_singleton_to_text,
        input_to_int,
        test_greater_or_equal(0),  # 0 means nothing.
        require,
      ),
      "VERSIONS_A_VENIR" => pipe(
        extract_singleton,
        empty_element_to_nothing,
      ),
    ),
    drop_nothing = true,
  ),
)


element_singleton_to_nota = @compat pipe(
  extract_singleton,
  test_isa(Dict),
  struct(
    Dict{String, Any}(
      "^tail" => pipe(
        test_isa(String),
        strip,
        test_nothing,
      ),
      "^text" => pipe(
        test_isa(String),
        strip,
        test_nothing,
      ),
      "CONTENU" => element_to_contenu,
    ),
    drop_nothing = true,
  ),
)


element_singleton_to_structure = @compat pipe(
  extract_singleton,
  test_isa(Dict),
  struct(
    Dict{String, Any}(
      "^tail" => pipe(
        test_isa(String),
        strip,
        test_nothing,
      ),
      "^text" => pipe(
        test_isa(String),
        strip,
        test_nothing,
      ),
      "LIEN_ART" => elements_array_to_liens_articles,
      "LIEN_SECTION_TA" => pipe(
        test_isa(Array),
        uniform_sequence(
          pipe(
            test_isa(Dict),
            struct(
              Dict{String, Any}(
                "^tail" => pipe(
                  test_isa(String),
                  strip,
                  test_nothing,
                ),
                "^text" => pipe(
                  test_isa(String),
                  strip,
                  require,
                ),
                "@cid" => pipe(
                  validate_cid,
                  require,
                ),
                "@debut" => pipe(
                  validate_date,
                  require,
                ),
                "@etat" => validate_etat,
                "@fin" => validate_date,
                "@id" => pipe(
                  validate_id,
                  require,
                ),
                "@niv" => pipe(
                  test_isa(String),
                  input_to_int,
                  test_between(1, 2),
                  require,
                ),
                "@url" => pipe(
                  validate_url,
                  require,
                ),
              ),
              drop_nothing = true,
            ),
            require,
          ),
        ),
      ),
    ),
    drop_nothing = true,
  ),
)


element_singleton_to_versions = @compat pipe(
  extract_singleton,
  test_isa(Dict),
  struct(
    Dict{String, Any}(
      "^tail" => pipe(
        test_isa(String),
        strip,
        test_nothing,
      ),
      "^text" => pipe(
        test_isa(String),
        strip,
        test_nothing,
      ),
      "VERSION" => pipe(
        test_isa(Array),
        uniform_sequence(
          pipe(
            test_isa(Dict),
            struct(
              Dict{String, Any}(
                "^tail" => pipe(
                  test_isa(String),
                  strip,
                  test_nothing,
                ),
                "^text" => pipe(
                  test_isa(String),
                  strip,
                  test_nothing,
                ),
                "@etat" => validate_etat,
                "LIEN_ART" => elements_array_to_liens_articles,
                "LIEN_TXT" => pipe(
                  extract_singleton,
                  test_isa(Dict),
                  struct(
                    Dict{String, Any}(
                      "^tail" => pipe(
                        test_isa(String),
                        strip,
                        test_nothing,
                      ),
                      "^text" => pipe(
                        test_isa(String),
                        strip,
                        test_nothing,
                      ),
                      "@debut" => validate_date,
                      "@fin" => validate_date,
                      "@id" => pipe(
                        validate_id,
                        require,
                      ),
                      "@num" => pipe(
                        validate_num,
                        require,
                      ),
                    ),
                    drop_nothing = true,
                  ),
                ),
              ),
              drop_nothing = true,
            ),
            require,
          ),
        ),
        require,
      ),
    ),
    drop_nothing = true,
  ),
)


element_to_article = @compat pipe(
  test_isa(Dict),
  struct(
    Dict{String, Any}(
      "^tail" => pipe(
        test_isa(String),
        strip,
        test_nothing,
      ),
      "^text" => pipe(
        test_isa(String),
        strip,
        test_nothing,
      ),
      "BLOC_TEXTUEL" => pipe(
        extract_singleton,
        test_isa(Dict),
        struct(
          Dict{String, Any}(
            "^tail" => pipe(
              test_isa(String),
              strip,
              test_nothing,
            ),
            "^text" => pipe(
              test_isa(String),
              strip,
              test_nothing,
            ),
            "CONTENU" => pipe(
              element_to_contenu,
              require,
            ),
          ),
          drop_nothing = true,
        ),
        require,
      ),
      "CONTEXTE" => pipe(
        element_singleton_to_contexte,
        require,
      ),
      "LIENS" => pipe(
        element_singleton_to_liens,
        require,
      ),
      "META" => pipe(
        extract_singleton,
        test_isa(Dict),
        struct(
          Dict{String, Any}(
            "^tail" => pipe(
              test_isa(String),
              strip,
              test_nothing,
            ),
            "^text" => pipe(
              test_isa(String),
              strip,
              test_nothing,
            ),
            "META_COMMUN" => pipe(
              element_singleton_to_meta_commun,
              require,
            ),
            "META_SPEC" => pipe(
              extract_singleton,
              test_isa(Dict),
              struct(
                Dict{String, Any}(
                  "^tail" => pipe(
                    test_isa(String),
                    strip,
                    test_nothing,
                  ),
                  "^text" => pipe(
                    test_isa(String),
                    strip,
                    test_nothing,
                  ),
                  "META_ARTICLE" => pipe(
                    extract_singleton,
                    test_isa(Dict),
                    struct(
                      Dict{String, Any}(
                        "^tail" => pipe(
                          test_isa(String),
                          strip,
                          test_nothing,
                        ),
                        "^text" => pipe(
                          test_isa(String),
                          strip,
                          test_nothing,
                        ),
                        "DATE_DEBUT" => pipe(
                          element_singleton_to_text,
                          validate_date,
                          require,
                        ),
                        "DATE_FIN" => pipe(
                          element_singleton_to_text,
                          validate_date,
                        ),
                        "ETAT" => pipe(
                          element_singleton_to_text,
                          validate_etat,
                        ),
                        "NUM" => pipe(
                          element_singleton_to_text,
                          validate_num,
                          require,
                        ),
                        "TYPE" => pipe(
                          element_singleton_to_text,
                          test_in(["AUTONOME", "ENTIEREMENT_MODIF", "PARTIELLEMENT_MODIF"]),
                          require,
                        ),
                      ),
                      drop_nothing = true,
                    ),
                    require,
                  ),
                ),
                drop_nothing = true,
              ),
              require,
            ),
          ),
          drop_nothing = true,
        ),
        require,
      ),
      "NOTA" => pipe(
        element_singleton_to_nota,
        require,
      ),
      "VERSIONS" => pipe(
        element_singleton_to_versions,
        require,
      ),
    ),
    drop_nothing = true,
  ),
)


element_to_section_ta = @compat pipe(
  test_isa(Dict),
  struct(
    Dict{String, Any}(
      "^tail" => pipe(
        test_isa(String),
        strip,
        test_nothing,
      ),
      "^text" => pipe(
        test_isa(String),
        strip,
        test_nothing,
      ),
      "CONTEXTE" => pipe(
        element_singleton_to_contexte,
        require,
      ),
      "ID" => pipe(
        element_singleton_to_text,
        validate_id,
        require,
      ),
      "STRUCTURE_TA" => pipe(
        element_singleton_to_structure,
        require,
      ),
      "TITRE_TA" => pipe(
        element_singleton_to_text,
        empty_to_nothing,
        require,
      ),
    ),
    drop_nothing = true,
  ),
)


element_to_texte_version = @compat pipe(
  test_isa(Dict),
  struct(
    Dict{String, Any}(
      "^tail" => pipe(
        test_isa(String),
        strip,
        test_nothing,
      ),
      "^text" => pipe(
        test_isa(String),
        strip,
        test_nothing,
      ),
      "ABRO" => pipe(
        extract_singleton,
        test_isa(Dict),
        struct(
          Dict{String, Any}(
            "^tail" => pipe(
              test_isa(String),
              strip,
              test_nothing,
            ),
            "^text" => pipe(
              test_isa(String),
              strip,
              test_nothing,
            ),
            "CONTENU" => element_to_contenu,
          ),
          drop_nothing = true,
        ),
        require,
      ),
      "META" => pipe(
        extract_singleton,
        test_isa(Dict),
        struct(
          Dict{String, Any}(
            "^tail" => pipe(
              test_isa(String),
              strip,
              test_nothing,
            ),
            "^text" => pipe(
              test_isa(String),
              strip,
              test_nothing,
            ),
            "META_COMMUN" => pipe(
              element_singleton_to_meta_commun,
              require,
            ),
            "META_SPEC" => pipe(
              extract_singleton,
              test_isa(Dict),
              struct(
                Dict{String, Any}(
                  "^tail" => pipe(
                    test_isa(String),
                    strip,
                    test_nothing,
                  ),
                  "^text" => pipe(
                    test_isa(String),
                    strip,
                    test_nothing,
                  ),
                  "META_TEXTE_CHRONICLE" => pipe(
                    element_singleton_to_meta_texte_chronicle,
                    require,
                  ),
                  "META_TEXTE_VERSION" => pipe(
                    extract_singleton,
                    test_isa(Dict),
                    struct(
                      Dict{String, Any}(
                        "^tail" => pipe(
                          test_isa(String),
                          strip,
                          test_nothing,
                        ),
                        "^text" => pipe(
                          test_isa(String),
                          strip,
                          test_nothing,
                        ),
                        "AUTORITE" => pipe(
                          extract_singleton,
                          empty_element_to_nothing,
                        ),
                        "DATE_DEBUT" => pipe(
                          element_singleton_to_text,
                          validate_date,
                          require,
                        ),
                        "DATE_FIN" => pipe(
                          element_singleton_to_text,
                          validate_date,
                        ),
                        "ETAT" => pipe(
                          element_singleton_to_text,
                          validate_etat,
                        ),
                        "LIENS" => element_singleton_to_liens,
                        "MINISTERE" => pipe(
                          element_singleton_to_text,
                          validate_ministere,
                        ),
                        "TITRE" => pipe(
                          element_singleton_to_text,
                          empty_to_nothing,
                          require,
                        ),
                        "TITREFULL" => pipe(
                          element_singleton_to_text,
                          empty_to_nothing,
                          require,
                        ),
                      ),
                      drop_nothing = true,
                    ),
                    require,
                  ),
                ),
                drop_nothing = true,
              ),
              require,
            ),
          ),
          drop_nothing = true,
        ),
        require,
      ),
      "NOTA" => pipe(
        element_singleton_to_nota,
        require,
      ),
      "RECT" => pipe(
        extract_singleton,
        test_isa(Dict),
        struct(
          Dict{String, Any}(
            "^tail" => pipe(
              test_isa(String),
              strip,
              test_nothing,
            ),
            "^text" => pipe(
              test_isa(String),
              strip,
              test_nothing,
            ),
            "CONTENU" => element_to_contenu,
          ),
          drop_nothing = true,
        ),
        require,
      ),
      "SIGNATAIRES" => pipe(
        extract_singleton,
        test_isa(Dict),
        struct(
          Dict{String, Any}(
            "^tail" => pipe(
              test_isa(String),
              strip,
              test_nothing,
            ),
            "^text" => pipe(
              test_isa(String),
              strip,
              test_nothing,
            ),
            "CONTENU" => element_to_contenu,
          ),
          drop_nothing = true,
        ),
        require,
      ),
      "TP" => pipe(
        extract_singleton,
        test_isa(Dict),
        struct(
          Dict{String, Any}(
            "^tail" => pipe(
              test_isa(String),
              strip,
              test_nothing,
            ),
            "^text" => pipe(
              test_isa(String),
              strip,
              test_nothing,
            ),
            "CONTENU" => element_to_contenu,
          ),
          drop_nothing = true,
        ),
        require,
      ),
      "VISAS" => pipe(
        extract_singleton,
        test_isa(Dict),
        struct(
          Dict{String, Any}(
            "^tail" => pipe(
              test_isa(String),
              strip,
              test_nothing,
            ),
            "^text" => pipe(
              test_isa(String),
              strip,
              test_nothing,
            ),
            "CONTENU" => element_to_contenu,
          ),
          drop_nothing = true,
        ),
        require,
      ),
    ),
    drop_nothing = true,
  ),
)


element_to_textelr = @compat pipe(
  test_isa(Dict),
  struct(
    Dict{String, Any}(
      "^tail" => pipe(
        test_isa(String),
        strip,
        test_nothing,
      ),
      "^text" => pipe(
        test_isa(String),
        strip,
        test_nothing,
      ),
      "META" => pipe(
        extract_singleton,
        test_isa(Dict),
        struct(
          Dict{String, Any}(
            "^tail" => pipe(
              test_isa(String),
              strip,
              test_nothing,
            ),
            "^text" => pipe(
              test_isa(String),
              strip,
              test_nothing,
            ),
            "META_COMMUN" => pipe(
              element_singleton_to_meta_commun,
              require,
            ),
            "META_SPEC" => pipe(
              extract_singleton,
              test_isa(Dict),
              struct(
                Dict{String, Any}(
                  "^tail" => pipe(
                    test_isa(String),
                    strip,
                    test_nothing,
                  ),
                  "^text" => pipe(
                    test_isa(String),
                    strip,
                    test_nothing,
                  ),
                  "META_TEXTE_CHRONICLE" => pipe(
                    element_singleton_to_meta_texte_chronicle,
                    require,
                  ),
                ),
                drop_nothing = true,
              ),
              require,
            ),
          ),
          drop_nothing = true,
        ),
        require,
      ),
      "STRUCT" => pipe(
        element_singleton_to_structure,
        require,
      ),
      "VERSIONS" => pipe(
        element_singleton_to_versions,
        require,
      ),
    ),
    drop_nothing = true,
  ),
)
