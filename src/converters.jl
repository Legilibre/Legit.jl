# Legit.jl -- Convert French law in LEGI format to Git & Markdown
# By: Emmanuel Raviart <emmanuel.raviart@data.gouv.fr>
#
# Copyright (C) 2015 Etalab
# https://github.com/etalab/Legit.jl
#
# The Legit.jl package is licensed under the MIT "Expat" License.


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
  test(cid -> ismatch(r"^(JORF|KALI|LEGI)(SCTA|TEXT)\d{12}$", cid); error = N_("Invalid CID.")),
)


validate_date = pipe(
  test_isa(String),
  empty_to_nothing,
  condition(
    test_equal(nothing),
    noop,
    test_equal("0003-05-19"),
    from_value(Date(1993, 5, 19)),
    test_equal("0881-10-09"),
    from_value(Date(1981, 10, 9)),
    test_equal("0958-09-10"),
    from_value(Date(1958, 9, 10)),
    test_equal("0988-11-30"),
    from_value(Date(1988, 11, 30)),
    test_equal("1006-06-21"),
    from_value(Date(2006, 6, 21)),
    test_equal("1192-10-19"),
    from_value(Date(1992, 10, 19)),
    test_equal("1193-03-24"),
    from_value(Date(1993, 3, 24)),
    test_equal("2222-02-02"),
    from_value(Date(2222, 2, 2)),
    test_equal("2222-02-22"),
    from_value(Date(2222, 2, 22)),
    test_equal("2999-01-01"),
    from_value(nothing),
    test_equal("5820-10-01"),
    from_value(nothing),
    iso8601_string_to_date,
  ),
)


validate_etat = pipe(
  test_isa(String),
  empty_to_nothing,
  test_in(["ABROGE", "ABROGE_DIFF", "ANNULE", "DISJOINT", "MODIFIE", "MODIFIE_MORT_NE", "PERIME", "TRANSFERE",
    "VIGUEUR", "VIGUEUR_DIFF"]),
)


validate_id = pipe(
  test_isa(String),
  empty_to_nothing,
  test(id -> ismatch(r"^(JORF|KALI|LEGI)(ARTI|CONT|SCTA|TEXT)\d{12}$", id); error = N_("Invalid ID.")),
)


validate_ministere = pipe(
  test_isa(String),
  empty_to_nothing,
  # TODO?
)


validate_nature = pipe(
  test_isa(String),
  empty_to_nothing,
  test_in(["ARRETE", "ARRETEEURO", "Article", "AVIS", "CIRCULAIRE", "CODE", "CONSTITUTION", "CONVENTION", "DECISION",
    "DECISION_EURO", "DECLARATION", "DECRET", "DECRETEURO", "DECRET_LOI", "DELIBERATION", "DIRECTIVE_EURO",
    "INSTRUCTION", "INSTRUCTIONEURO", "LOI", "LOI_CONSTIT", "LOI_ORGANIQUE", "LOI_PROGRAMME", "ORDONNANCE", "RAPPORT",
    "REGLEMENTEUROPEEN"]),
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


element_to_lien_article = @compat pipe(
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
      "@num" => validate_num,
      "@origine" => pipe(
        validate_origine,
        require,
      ),
    ),
    drop_nothing = true,
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
            "@date_publi" => validate_date,
            "@date_signature" => validate_date,
            "@ministere" => validate_ministere,
            "@nature" => pipe(
              validate_nature,
              require,
            ),
            "@nor" => validate_nor,
            "@num" => validate_num,
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
                  test_in(["ABROGATION", "ABROGE", "ANNULATION", "ANNULE", "APPLICATION", "CITATION", "CODIFICATION",
                    "CODIFIE", "CONCORDANCE", "CONCORDE", "CREATION", "CREE", "DEPLACE", "DEPLACEMENT", "DISJOINT",
                    "DISJONCTION", "HISTO", "MODIFICATION", "MODIFIE", "PEREMPTION", "PERIME", "PILOTE_SUIVEUR",
                    "RATIFICATION", "RATIFIE", "RECTIFICATION", "SPEC_APPLI", "SUBSTITUTION", "TRANSFERE", "TRANSFERT",
                    "TRANSPOSITION", "TXT_ASSOCIE", "TXT_SOURCE"]),
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
      ),
      "DERNIERE_MODIFICATION" => pipe(
        element_singleton_to_text,
        validate_date,
      ),
      "NOR" => pipe(
        element_singleton_to_text,
        validate_nor,
      ),
      "NUM" => pipe(
        element_singleton_to_text,
        validate_num,
      ),
      "NUM_SEQUENCE" => pipe(
        element_singleton_to_text,
        input_to_int,
        test_greater_or_equal(0),  # 0 means nothing.
      ),
      "ORIGINE_PUBLI" => pipe(
        element_singleton_to_text,
        empty_to_nothing,
      ),
      "PAGE_DEB_PUBLI" => pipe(
        element_singleton_to_text,
        input_to_int,
        test_greater_or_equal(0),  # 0 means nothing.
      ),
      "PAGE_FIN_PUBLI" => pipe(
        element_singleton_to_text,
        input_to_int,
        test_greater_or_equal(0),  # 0 means nothing.
      ),
      "VERSIONS_A_VENIR" => pipe(
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
            "VERSION_A_VENIR" => pipe(
              test_isa(Array),
              uniform_sequence(
                pipe(
                  element_to_text,
                  validate_date,
                  require,
                ),
              ),
              empty_to_nothing,
            ),
          ),
          drop_nothing = true,
        ),
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
      "LIEN_ART" => pipe(
        test_isa(Array),
        uniform_sequence(
          pipe(
            element_to_lien_article,
            require,
          ),
        ),
        call(links -> sort!(links; by = link -> begin
          start_date = get(link, "@debut") do
            return Date(2999, 1, 1)
          end
          stop_date = get(link, "@fin") do
            return Date(2999, 1, 1)
          end
          return (get(link, "@num", ""), min(start_date, stop_date), stop_date, link["@id"])
        end)),
      ),
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
                "@debut" => validate_date,
                "@etat" => validate_etat,
                "@fin" => validate_date,
                "@id" => pipe(
                  validate_id,
                  require,
                ),
                "@niv" => pipe(
                  test_isa(String),
                  input_to_int,
                  test_between(1, 13),
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
                "LIEN_ART" => pipe(
                  extract_singleton,
                  element_to_lien_article,
                ),
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
                      "@num" => validate_num,
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
        call(versions -> sort!(versions; by = version -> begin
          link = get(version, "LIEN_ART") do
            return version["LIEN_TXT"]
          end
          start_date = get(link, "@debut") do
            return Date(2999, 1, 1)
          end
          stop_date = get(link, "@fin") do
            return Date(2999, 1, 1)
          end
          return (min(start_date, stop_date), link["@id"])
        end)),
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
      "COMMENTAIRE" => pipe(
        element_singleton_to_text,
        empty_to_nothing,
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
