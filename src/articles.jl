# Legit.jl -- Convert French law in LEGI format to Git & Markdown
# By: Emmanuel Raviart <emmanuel.raviart@data.gouv.fr>
#
# Copyright (C) 2015 Etalab
# https://github.com/etalab/Legit.jl
#
# The Legit.jl package is licensed under the MIT "Expat" License.


const number_by_latin_extension = @compat Dict{String, String}(
  "bis" => "0002",
  "ter" => "0003",
  "quater" => "0004",
  "quinquies" => "0005",
  "sexies" => "0006",
  "septies" => "0007",
  "octies" => "0008",
  "nonies" => "0009",
  "decies" => "0010",
  "undecies" => "0011",
  "duodecies" => "0012",
  "terdecies" => "0013",
  "quaterdecies" => "0014",
  "quindecies" => "0015",
  "quinquedecies" => "0015",
  "sexdecies" => "0016",
  "septdecies" => "0017",
  "octodecies" => "0018",
  "novodecies" => "0019",
  "vicies" => "0020",
  "unvicies" => "0021",
  "duovicies" => "0022",
  "tervicies" => "0023",
  "quatervicies" => "0024",
  "quinvicies" => "0025",
  "sexvicies" => "0026",
  "septvicies" => "0027",
  "octovicies" => "0028",
  "novovicies" => "0029",
  "tricies" => "0030",
  "untricies" => "0031",
  "duotricies" => "0032",
  "tertricies" => "0033",
  "quatertricies" => "0034",
  "quintricies" => "0035",
  "sextricies" => "0036",
  "septtricies" => "0037",
  "octotricies" => "0038",
  "novotricies" => "0039",
)

const number_by_slug = @compat Dict{String, String}(
  "premier" => "0001",
  "premiere" => "0001",
  "deuxieme" => "0002",
  "troisieme" => "0003",
  "quatrieme" => "0004",
  "cinquieme" => "0005",
  "sixieme" => "0006",
  "septieme" => "0007",
  "huitieme" => "0008",
  "neuvieme" => "0009",
  "dixieme" => "0010",
)


abstract Node
abstract AbstractTableOfContent <: Node


@compat type Article <: Node
  container::AbstractTableOfContent
  date_debut::Union(Date, Nothing)
  date_fin::Union(Date, Nothing)
  dict::Dict  # Dict{String, Any}
  next_version::Nullable{Article}  # Next version of the same article (may have the same ID)

end

Article(container::AbstractTableOfContent, date_debut::Union(Date, Nothing), date_fin::Union(Date, Nothing),
  dict::Dict) = @compat Article(container, date_debut, date_fin, dict, Nullable{Article}())


type Changed
  articles::Array{Article}
  deleted_articles::Array{Article}

  Changed() = new(Article[], Article[])
end


type Document <: AbstractTableOfContent
  container::Node  # TODO: Nature or Section
  texte_version::Dict  # Dict{String, Any}
  textelr::Dict  # Dict{String, Any}
end


type Nature <: Node
  title::String
end


# type NonArticle
#   title::String
#   content::XMLElement
# end


type Section <: Node
  sortable_title::String
  title::String
  child_by_name::Dict{String, Node}

  Section(sortable_title::String, title::String) = new(sortable_title, title, @compat Dict{String, Node}())
end

Section() = Section("", "")


type TableOfContent <: AbstractTableOfContent
  container::AbstractTableOfContent
  date_debut::Union(Date, Nothing)
  date_fin::Union(Date, Nothing)
  dict::Dict  # Dict{String, Any}
end


function commonmark(article::Article, mode::String; depth::Int = 1)
  blocks = String[
    "#" ^ depth,
    " ",
    node_title(article),
    "\n\n",
  ]
  content = commonmark(article.dict["BLOC_TEXTUEL"]["CONTENU"])
  content = join(map(strip, split(content, '\n')), '\n')
  while searchindex(content, "\n\n\n") > 0
    content = replace(content, "\n\n\n", "\n\n")
  end
  push!(blocks, strip(content))
  push!(blocks, "\n")
  return join(blocks)
end

# function commonmark(non_article::NonArticle, mode::String; depth::Int = 1)
#   blocks = String[]
#   if !isempty(non_article.title)
#     push!(blocks,
#       "#" ^ depth,
#       " ",
#       non_article.title,
#       "\n\n",
#     )
#   end
#   content = commonmark(non_article.dict["BLOC_TEXTUEL"]["CONTENU"])
#   content = join(map(strip, split(content, '\n')), '\n')
#   while searchindex(content, "\n\n\n") > 0
#     content = replace(content, "\n\n\n", "\n\n")
#   end
#   push!(blocks, strip(content))
#   push!(blocks, "\n\n")
#   return join(blocks)
# end

commonmark(section::Section, mode::String; depth::Int = 1) = string(
  "#" ^ depth,
  " ",
  node_title(section),
  "\n",
  commonmark_children(section, mode; depth = depth),
)

function commonmark(xhtml_element::XMLElement; depth::Int = 1)
  blocks = String[]
  for xhtml_node in child_nodes(xhtml_element)
    if is_textnode(xhtml_node)
      push!(blocks, content(xhtml_node))
    elseif is_elementnode(xhtml_node)
      xhtml_child = XMLElement(xhtml_node)
      child_name = name(xhtml_child)
      if child_name == "blockquote"
        push!(blocks, "\n")
        child_text = commonmark(xhtml_child, depth = depth)
        push!(blocks, join(map(line -> string("> ", strip(line)), split(strip(child_text), '\n')), '\n'))
        push!(blocks, "\n")
      elseif child_name == "br"
        push!(blocks, "\n\n")
      elseif child_name in ("div", "font", "sup", "table")
        push!(blocks, string(xhtml_child))
      elseif child_name in ("em", "i")
        content_commonmark = strip(commonmark(xhtml_child, depth = depth))
        if !isempty(content_commonmark)
          push!(blocks, "_")
          push!(blocks, content_commonmark)
          push!(blocks, "_")
        end
      elseif child_name in ("h1", "h2", "h3", "h4", "h5")
        content_commonmark = strip(commonmark(xhtml_child, depth = depth))
        if !isempty(content_commonmark)
          push!(blocks, "#" ^ (parseint(child_name[2]) + 1))
          push!(blocks, content_commonmark)
          push!(blocks, "\n\n")
        end
      elseif child_name == "p"
        push!(blocks, "\n\n")
        content_commonmark = rstrip(commonmark(xhtml_child, depth = depth))
        if !isempty(content_commonmark)
          push!(blocks, content_commonmark)
          push!(blocks, "\n\n")
        end
      elseif child_name in ("b", "strong")
        content_commonmark = strip(commonmark(xhtml_child, depth = depth))
        if !isempty(content_commonmark)
          push!(blocks, "**")
          push!(blocks, content_commonmark)
          push!(blocks, "**")
        end
      else
        error("Unexpected XHTML element $child_name in:\n$(string(xhtml_element)).")
      end
    end
  end
  return join(blocks)
end


commonmark_children(article::Article, mode::String; depth::Int = 1, link_prefix::String = "") = ""

function commonmark_children(section::Section, mode::String; depth::Int = 1, link_prefix::String = "")
  blocks = String[
    "\n",
  ]
  children_infos = [
    (node_sortable_title(child), name, child)
    for (name, child) in section.child_by_name
  ]
  sort!(children_infos)
  if mode == "single-page"
    for (index, (sortable_number, name, child)) in enumerate(children_infos)
      if index > 1
        push!(blocks, "\n")
      end
      push!(blocks, commonmark(child, mode; depth = depth + 1))
    end
  else
    indent = "  " ^ depth
    for (sortable_number, name, child) in children_infos
      push!(blocks, "$(indent)- [$(node_title(child))]($link_prefix$name)\n")
      if mode == "deep-readme"
        push!(blocks, commonmark_children(child, mode; depth = depth + 1, link_prefix = string(link_prefix, name, '/')))
      end
    end
  end
  return join(blocks)
end


function link_articles(articles_by_id)
  for (article_id, same_id_articles) in articles_by_id
    sort!(same_id_articles, by = article -> min_date(node_start_date(article), node_stop_date(article)))
  end
  for (article_id, same_id_articles) in articles_by_id
    for (article_index, article) in enumerate(same_id_articles)
      previous_article_with_same_id = article_index == 1 ? nothing : same_id_articles[article_index - 1]
      versions = article.dict["VERSIONS"]["VERSION"]
      version_index = findfirst(version -> version["LIEN_ART"]["@id"] == article_id, versions)
      if version_index > 1
        previous_version_article = nothing
        previous_version_article_index = 0
        previous_version_index = version_index - 1
        while previous_version_index > 0
          previous_version_id = versions[previous_version_index]["LIEN_ART"]["@id"]
          previous_version_articles = get(articles_by_id, previous_version_id, Article[])
          # Note: When previous_version_articles is empty, the article has an empty date interval. Skip it.
          if !isempty(previous_version_articles)
            previous_version_article_index = findlast(previous_version_articles) do previous_version_article
              return min_date(node_start_date(previous_version_article), node_stop_date(previous_version_article)) <
                min_date(node_start_date(article), node_stop_date(article))
            end
            if previous_version_article_index > 0
              previous_version_article = previous_version_articles[previous_version_article_index]
            end
            break
          end
          previous_version_index -= 1
        end
        previous_article = previous_article_with_same_id === nothing ?
          previous_version_article :
          previous_version_article !== nothing &&
              min_date(node_start_date(previous_article_with_same_id), node_stop_date(previous_article_with_same_id)) <
              min_date(node_start_date(previous_version_article), node_stop_date(previous_version_article)) ?
            previous_version_article :
            previous_article_with_same_id
      else
        previous_article = previous_article_with_same_id
      end
      if previous_article !== nothing
        if isnull(previous_article.next_version)
          previous_article.next_version = Nullable(article)
        else
          article_start_date = node_start_date(article)
          next_article = get(previous_article.next_version)
          next_article_start_date = node_start_date(next_article)
          warn(string(
            "Previous article ",
            node_id(previous_article),
            '@',
            node_start_date(previous_article),
            '-',
            node_stop_date(previous_article),
            " of ",
            article_id,
            '@',
            article_start_date,
            '-',
            node_stop_date(article),
            " already has a next version ",
            node_id(next_article),
            '@',
            next_article_start_date,
            '-',
            node_stop_date(next_article),
          ))
          if article_start_date < next_article_start_date
            previous_article.next_version = Nullable(article)
            article.next_version = Nullable(next_article)
          else
            @assert isnull(next_article.next_version)
            next_article.next_version = Nullable(article)
          end
        end
      end
    end
  end
end


function load_article(dir::String, id::String)
  article_file_path = joinpath(dir, "article", id[1:4], id[5:8], id[9:10], id[11:12], id[13:14], id[15:16], id[17:18],
    id * ".xml")
  article_xml_document = parse_file(article_file_path)
  return Convertible(parse_xml_element(root(article_xml_document))) |> pipe(
    element_to_article,
    require,
  ) |> to_value
end


max_date(left::Date, right::Date) = max(left, right)

max_date(left::Date, ::Nothing) = left

max_date(::Nothing, right::Date) = right

max_date(::Nothing, ::Nothing) = nothing


min_date(left::Date, right::Date) = min(left, right)

min_date(left::Date, ::Nothing) = left

min_date(::Nothing, right::Date) = right

min_date(::Nothing, ::Nothing) = nothing


node_dir_name(nature::Nature) = slugify(node_title_short(nature); separator = '_')

node_dir_name(table_of_content::Document) = slugify(node_title_short(table_of_content); separator = '_')

node_dir_name(table_of_content::TableOfContent) = slugify(node_number_and_simple_title(node_title_short(
  table_of_content))[2]; separator = '_')


node_filename(article::Article) = string("article_", slugify(node_number(article)), ".md")

node_filename(node::Node) = node_dir_name(node) * ".md"


function node_git_dir(table_of_content::AbstractTableOfContent)
  container_git_dir = node_git_dir(table_of_content.container)
  dir_name = node_dir_name(table_of_content)
  return isempty(container_git_dir) ? dir_name : string(container_git_dir, '/', dir_name)
end

node_git_dir(article::Article) = node_git_dir(article.container)

node_git_dir(nature::Nature) = node_dir_name(nature)


node_git_file_path(node::Node) = string(node_git_dir(node), '/', node_filename(node))


node_id(article::Article) = article.dict["META"]["META_COMMUN"]["ID"]

node_id(document::Document) = document.texte_version["META"]["META_COMMUN"]["ID"]

node_id(table_of_content::TableOfContent) = table_of_content.dict["ID"]

node_id(node_dict::Dict) = node_dict["META"]["META_COMMUN"]["ID"]


node_name(table_of_content::AbstractTableOfContent) = node_dir_name(table_of_content)

node_name(article::Article) = node_filename(article)

node_name(nature::Nature) = node_dir_name(nature)


node_number(table_of_content::AbstractTableOfContent) = node_number(node_title_short(table_of_content))

node_number(article::Article) = article.dict["META"]["META_SPEC"]["META_ARTICLE"]["NUM"]

node_number(section::Section) = node_number(node_title_short(section))

node_number(title::String) = node_number_and_simple_title(title)[1]


node_number_and_simple_title(table_of_content::AbstractTableOfContent) = node_number_and_simple_title(node_title_short(
  table_of_content))

function node_number_and_simple_title(title::String)
  number_fragments = String[]
  simple_title_fragments = String[]
  for fragment in split(strip(title))
    fragment_lower = lowercase(fragment)
    if fragment_lower == "n°"
      continue
    end
    if startswith(fragment_lower, "n°")
      fragment = fragment[3:end]
      fragment_lower = fragment_lower[3:end]
    end
    slug = slugify(fragment_lower)
    if slug in ("chapitre", "livre", "paragraphe", "partie", "section", "sous-paragraphe", "sous-section",
        "sous-sous-paragraphe", "titre")
      push!(simple_title_fragments, fragment)
    elseif slug in ("annexe", "legislative", "preliminaire", "reglementaire", "rubrique", "sommaire", "suite",
        "tableau")
      # Partie législative, partie réglementaire, chapître préliminaire
      push!(number_fragments, fragment)
      push!(simple_title_fragments, fragment)
    elseif isdigit(fragment) || slug in ("ier", "unique") || ismatch(r"^[ivxlcdm]+$",fragment_lower) ||
        slug in keys(number_by_latin_extension) || slug in keys(number_by_slug) ||
        length(slug) <= 3 && all(letter -> 'a' <= letter <= 'z', slug) &&
          !(slug in ("de", "des", "du", "la", "le", "les")) ||
        2 <= length(slug) <= 5 && 'a' <= slug[1] <= 'z' && isdigit(slug[2 : end]) ||
        3 <= length(slug) <= 6 && all(letter -> 'a' <= letter <= 'z', slug[1 : 2]) && isdigit(slug[3 : end])
      push!(number_fragments, fragment)
      push!(simple_title_fragments, fragment)
    elseif isempty(number_fragments)
      push!(simple_title_fragments, fragment)
    else
      break
    end
  end
  @assert !isempty(simple_title_fragments) "Empty simplification of title for: $title."
  return join(number_fragments, ' '), join(simple_title_fragments, ' ')
end


node_sortable_title(article::Article) = node_sortable_title(node_number(article), node_title_short(article))

node_sortable_title(document::Document) = slugify(document.container.title) == "code" ? node_title_short(document) :
  node_sortable_title(node_number_and_simple_title(document)...)

node_sortable_title(nature::Nature) = node_title_short(nature)

node_sortable_title(section::Section) = section.sortable_title

node_sortable_title(table_of_content::TableOfContent) = node_sortable_title(node_number_and_simple_title(
  table_of_content)...)

function node_sortable_title(number::String, simple_title::String)
  if isempty(number)
    return slugify(simple_title)
  end
  number_fragments = String[]
  slug = slugify(number; separator = '_')
  slug = replace(slug, "_a_l_article_", "_")
  for fragment in split(slug, '_')
    if isdigit(fragment)
      @assert length(fragment) <= 4
      push!(number_fragments, ("0000" * fragment)[end - 3 : end])
    elseif fragment == "preliminaire"
      push!(number_fragments, "0000")
    elseif fragment in ("ier", "legislative", "unique")
      push!(number_fragments, "0001")
    elseif fragment in ("reglementaire", "suite")
      push!(number_fragments, "0002")
    elseif fragment == "rubrique"
      push!(number_fragments, "7000")
    elseif fragment == "sommaire"
      push!(number_fragments, "8000")
    elseif fragment == "annexe"
      push!(number_fragments, "9000")
    elseif fragment == "tableau"
      push!(number_fragments, "9500")
    elseif ismatch(r"^[ivxlcdm]+$", fragment)
      value = 0
      for letter in fragment
        digit = [
          'i' => 1,
          'v' => 5,
          'x' => 10,
          'l' => 50,
          'c' => 100,
          'd' => 500,
          'm' => 1000,
        ][letter]
        if digit > value
          value = digit - value
        else
          value += digit
        end
      end
      @assert value < 10000
      push!(number_fragments, string("0000", value)[end - 3 : end])
    else
      number = get(number_by_latin_extension, fragment, "")
      if !isempty(number)
        push!(number_fragments, number)
      else
        number = get(number_by_slug, fragment, "")
        if !isempty(number)
          push!(number_fragments, number)
        elseif length(fragment) <= 3 && all(letter -> 'a' <= letter <= 'z', fragment) ||
            length(fragment) <= 3 && all(letter -> 'a' <= letter <= 'z', fragment) &&
              !(fragment in ("de", "des", "du", "la", "le", "les"))
          push!(number_fragments, fragment)
        elseif 2 <= length(fragment) <= 5 && 'a' <= fragment[1] <= 'z' && isdigit(fragment[2 : end])
          push!(number_fragments, fragment[1 : 1])
          push!(number_fragments, string("0000", fragment[2 : end])[end - 3 : end])
        elseif 3 <= length(fragment) <= 6 && all(letter -> 'a' <= letter <= 'z', fragment[1 : 2]) &&
            isdigit(fragment[3 : end])
          push!(number_fragments, fragment[1 : 2])
          push!(number_fragments, string("0000", fragment[3 : end])[end - 3 : end])
        else
          push!(number_fragments, fragment)
        end
      end
    end
  end
  return join(number_fragments, '-')
end


node_start_date(article::Article) = article.date_debut

node_start_date(document::Document) = get(document.texte_version["META"]["META_SPEC"]["META_TEXTE_VERSION"],
  "DATE_DEBUT", nothing)

node_start_date(table_of_content::TableOfContent) = table_of_content.date_debut


function node_stop_date(node::Union(Article, TableOfContent))
  stop_date = node.date_fin
  if stop_date !== nothing && stop_date < node.date_debut
    # May occur when ETAT = MODIFIE_MORT_NE.
    stop_date = node.date_debut
  end
  return stop_date
end

node_stop_date(document::Document) = get(document.texte_version["META"]["META_SPEC"]["META_TEXTE_VERSION"],
  "DATE_FIN", nothing)


node_structure(table_of_content::Document) = table_of_content.textelr["STRUCT"]

node_structure(table_of_content::TableOfContent) = table_of_content.dict["STRUCTURE_TA"]


node_title(article::Article) = string("Article ", node_number(article))

node_title(nature::Nature) = nature.title

node_title(section::Section) = section.title

node_title(table_of_content::Document) = table_of_content.texte_version["META"]["META_SPEC"][
  "META_TEXTE_VERSION"]["TITREFULL"]

node_title(table_of_content::TableOfContent) = table_of_content.dict["TITRE_TA"]


node_title_short(table_of_content::Document) = table_of_content.texte_version["META"]["META_SPEC"][
  "META_TEXTE_VERSION"]["TITRE"]

node_title_short(node::Node) = node_title(node)


function parse_structure(articles_by_id::Dict{String, Vector{Article}},
    changed_by_message_by_date::Dict{Date, OrderedDict{String, Changed}}, dir::String,
    table_of_content::AbstractTableOfContent)
  structure = node_structure(table_of_content)
  table_of_content_start_date = node_start_date(table_of_content)
  if table_of_content_start_date === nothing
    return
  end
  table_of_content_stop_date = node_stop_date(table_of_content)

  for lien_section_ta in get(structure, "LIEN_SECTION_TA", Dict{String, Any}[])
    lien_start_date = get(lien_section_ta, "@debut", nothing)
    if lien_start_date === nothing
      continue
    end
    if table_of_content_stop_date !== nothing && lien_start_date >= table_of_content_stop_date
      continue
    end
    lien_stop_date = get(lien_section_ta, "@fin", nothing)
    if lien_stop_date !== nothing && (lien_stop_date <= table_of_content_start_date ||
        lien_stop_date <= lien_start_date)
      continue
    end

    section_ta = nothing
    section_ta_file_path = joinpath(dir, "section_ta" * lien_section_ta["@url"])
    try
      section_ta_xml_document = parse_file(section_ta_file_path)
      section_ta = Convertible(parse_xml_element(root(section_ta_xml_document))) |> pipe(
        element_to_section_ta,
        require,
      ) |> to_value
    catch
      warn("An exception occured in file $section_ta_file_path.")
      rethrow()
    end
    child_table_of_content = TableOfContent(table_of_content, max_date(table_of_content_start_date, lien_start_date),
      min_date(table_of_content_stop_date, lien_stop_date), section_ta)
    parse_structure(articles_by_id, changed_by_message_by_date, dir, child_table_of_content)
  end

  for lien_article in get(structure, "LIEN_ART", Dict{String, Any}[])
    lien_start_date = get(lien_article, "@debut", nothing)
    if lien_start_date === nothing
      continue
    end
    if table_of_content_stop_date !== nothing && lien_start_date >= table_of_content_stop_date
      continue
    end
    lien_stop_date = get(lien_article, "@fin", nothing)
    if lien_stop_date !== nothing && (lien_stop_date <= table_of_content_start_date ||
        lien_stop_date <= lien_start_date)
      continue
    end

    article_id = lien_article["@id"]
    article_dict = load_article(dir, article_id)
    meta_article = article_dict["META"]["META_SPEC"]["META_ARTICLE"]
    article = Article(table_of_content, max_date(table_of_content_start_date, lien_start_date),
      min_date(table_of_content_stop_date, lien_stop_date), article_dict)
    same_id_articles = get!(articles_by_id, article_id) do
      return Article[]
    end
    push!(same_id_articles, article)

    try
      start_messages = String[]
      stop_messages = String[]
      for lien in get(article_dict["LIENS"], "LIEN", Dict{String, Any}[])
        if get(lien, "@datesignatexte", nothing) === nothing
          continue
        end

        if lien["@sens"] == "cible" && lien["@typelien"] in ("CREE", "DEPLACE", "MODIFIE") ||
            lien["@sens"] == "source" && lien["@typelien"] in ("MODIFICATION", "TRANSPOSITION")
          if meta_article["DATE_DEBUT"] <= lien["@datesignatexte"]
            info("Unexpected date $(lien["@datesignatexte"]) after DATE_DEBUT article $(meta_article["DATE_DEBUT"]) " *
              "in $article_id for: $lien. Ignoring link...")
          else
            message = split(lien["^text"], " - ")[1]
            if !(message in start_messages)
              push!(start_messages, message)
            end
          end
        elseif lien["@sens"] == "source" && lien["@typelien"] in ("ABROGATION", "DISJONCTION", "PEREMPTION",
            "SUBSTITUTION", "TRANSFERT") ||
            lien["@sens"] == "cible" && lien["@typelien"] in ("ABROGE", "DISJOINT", "PERIME", "TRANSFERE")
          stop_date = get(meta_article, "DATE_FIN", nothing)
          if stop_date !== nothing
            if stop_date <= lien["@datesignatexte"]
              info("Unexpected date $(lien["@datesignatexte"]) after DATE_FIN article $(stop_date) in " *
                "$article_id for: $lien. Ignoring link...")
            else
              message = split(lien["^text"], " - ")[1]
              if !(message in stop_messages)
                push!(stop_messages, message)
              end
            end
          end
        end
      end

      creation_date = node_start_date(article)
      @assert creation_date !== nothing
      if isempty(start_messages)
        push!(start_messages, "Modifications d'origine indéterminée")
      end
      changed_by_message = get!(changed_by_message_by_date, creation_date) do
        return OrderedDict{String, Changed}()
      end
      # OrderedDict doesn't support this get! signature.
      # changed = get!(changed_by_message, join(start_messages, ", ", " et ")) do
      #   return Changed()
      # end
      start_message = join(start_messages, ", ", " et ")
      changed = get(changed_by_message, start_message, nothing)
      if changed === nothing
        changed_by_message[start_message] = changed = Changed()
      end
      push!(changed.articles, article)

      deletion_date = node_stop_date(article)
      if deletion_date !== nothing
        if isempty(stop_messages)
          push!(stop_messages, "Suppressions d'origine indéterminée")
        end
        changed_by_message = get!(changed_by_message_by_date, deletion_date) do
          return OrderedDict{String, Changed}()
        end
        # OrderedDict doesn't support this get! signature.
        # changed = get!(changed_by_message, join(stop_messages, ", ", " et ")) do
        #   return Changed()
        # end
        stop_message = join(stop_messages, ", ", " et ")
        changed = get(changed_by_message, stop_message, nothing)
        if changed === nothing
          changed_by_message[stop_message] = changed = Changed()
        end
        push!(changed.deleted_articles, article)
      end
    catch
      warn("An exception occured in $(node_filename(article)) [$(get(meta_article, "ETAT", "inconnu"))]: $article_id.")
      rethrow()
    end
  end
end


function parse_xml_element(xml_element::XMLElement)
  element = @compat Dict{String, Any}()
  for attribute in attributes(xml_element)
    element[string('@', name(attribute))] = value(attribute)
  end
  previous = element
  for xml_node in child_nodes(xml_element)
    if is_textnode(xml_node)
      if previous === element
        element["^text"] = get(element, "^text", "") * content(xml_node)
      else
        previous["^tail"] = get(element, "^tail", "") * content(xml_node)
      end
    elseif is_elementnode(xml_node)
      xml_child = XMLElement(xml_node)
      child_name = name(xml_child)
      if child_name == "CONTENU"
        @assert !(child_name in element)
        element[child_name] = xml_child
      else
        child = parse_xml_element(xml_child)
        same_children = get!(element, child_name) do
          return Dict{String, Any}[]
        end
        push!(same_children, child)
        previous = child
      end
    end
  end
  return element
end
