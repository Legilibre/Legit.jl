# Legit.jl -- Convert French law in LEGI format to Git & Markdown
# By: Emmanuel Raviart <emmanuel.raviart@data.gouv.fr>
#
# Copyright (C) 2015 Etalab
# https://github.com/etalab/Legit.jl
#
# The GitLegistique.jl package is licensed under the MIT "Expat" License.


abstract AbstractTableOfContent


type RootTableOfContent <: AbstractTableOfContent
  texte_version::Dict  # Dict{String, Any}
  textelr::Dict  # Dict{String, Any}
end


type TableOfContent <: AbstractTableOfContent
  container::AbstractTableOfContent
  dict::Dict  # Dict{String, Any}
end


type Article
  container::TableOfContent
  dict::Dict  # Dict{String, Any}
end


type Changed
  articles::Array{Article}
  deleted_articles::Array{Article}

  Changed() = new(Article[], Article[])
end


immutable Changer
  date::Date
  message::String
end


type NonArticle
  title::String
  content::XMLElement
end


type Section
  title::String
  children::Array{Union(Article, NonArticle, Section)}
end


function all_in_one_commonmark(article::Article; depth::Int = 1)
  blocks = String[
    "#" ^ depth,
    " ",
    "Article ",
    article.dict["META"]["META_SPEC"]["META_ARTICLE"]["NUM"],
    "\n\n",
  ]
  content = all_in_one_commonmark(article.dict["BLOC_TEXTUEL"]["CONTENU"])
  content = join(map(strip, split(content, '\n')), '\n')
  while searchindex(content, "\n\n\n") > 0
    content = replace(content, "\n\n\n", "\n\n")
  end
  push!(blocks, strip(content))
  push!(blocks, "\n")
  return join(blocks)
end

function all_in_one_commonmark(non_article::NonArticle; depth::Int = 1)
  blocks = String[]
  if !isempty(non_article.title)
    push!(blocks,
      "#" ^ depth,
      " ",
      non_article.title,
      "\n\n",
    )
  end
  content = all_in_one_commonmark(non_article.dict["BLOC_TEXTUEL"]["CONTENU"])
  content = join(map(strip, split(content, '\n')), '\n')
  while searchindex(content, "\n\n\n") > 0
    content = replace(content, "\n\n\n", "\n\n")
  end
  push!(blocks, strip(content))
  push!(blocks, "\n\n")
  return join(blocks)
end

function all_in_one_commonmark(section::Section; depth::Int = 1)
  blocks = String[]
  if !isempty(section.title)
    push!(blocks,
      "#" ^ depth,
      " ",
      section.title,
      "\n\n",
    )
  end
  for child in section.children
    push!(blocks, all_in_one_commonmark(child, depth = depth + 1))
  end
  return join(blocks)
end

function all_in_one_commonmark(xhtml_element::XMLElement; depth::Int = 1)
  blocks = String[]
  for xhtml_node in child_nodes(xhtml_element)
    if is_textnode(xhtml_node)
      push!(blocks, content(xhtml_node))
    elseif is_elementnode(xhtml_node)
      xhtml_child = XMLElement(xhtml_node)
      child_name = name(xhtml_child)
      if child_name == "blockquote"
        push!(blocks, "\n")
        child_text = all_in_one_commonmark(xhtml_child, depth = depth)
        push!(blocks, join(map(line -> string("> ", strip(line)), split(strip(child_text), '\n')), '\n'))
        push!(blocks, "\n")
      elseif child_name == "br"
        push!(blocks, "\n\n")
      elseif child_name == "div"
        push!(blocks, string(xhtml_child))
      elseif child_name == "p"
        push!(blocks, "\n\n")
        push!(blocks, all_in_one_commonmark(xhtml_child, depth = depth))
        push!(blocks, "\n\n")
      else
        error("Unexpected XHTML element $child_name in:\n$(string(xhtml_element)).")
      end
    end
  end
  return join(blocks)
end


dir_name(table_of_content::RootTableOfContent) = ""

dir_name(table_of_content::TableOfContent) = slugify(table_of_content_title(table_of_content); separator = '_')


git_dir(article::Article) = git_dir(article.dict["CONTEXTE"]["TEXTE"]["TM"])

function git_dir(tm::Dict)
  slug = slugify(tm["TITRE_TM"]["^text"]; separator = '_')
  tm = get(tm, "TM", nothing)
  return tm === nothing ? slug : string(slug, '/', git_dir(tm))
end

git_dir(table_of_content::RootTableOfContent) = ""

git_dir(table_of_content::TableOfContent) = lstrip(
  string(git_dir(table_of_content.container), '/', dir_name(table_of_content)), '/')


hash(changer::Changer, h::Uint64) = hash(changer.date, h) $ hash(changer.message, h)


function isequal(left::Changer, right::Changer)
  return left.date == right.date && left.message == right.message
end


function isless(left::Changer, right::Changer)
  return left.date < right.date || left.date == right.date && left.message < right.message
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


function repair_article_creation_date(creation_date::Date, contexte::Dict)
  tm = get(contexte, "TM", nothing)
  if tm === nothing
    return creation_date
  end
  return repair_article_creation_date(max(creation_date, tm["TITRE_TM"]["@debut"]), tm)
end


function repair_article_deletion_date(deletion_date::Date, contexte::Dict)
  tm = get(contexte, "TM", nothing)
  if tm === nothing
    return deletion_date
  end
  date = get(tm["TITRE_TM"], "@fin", nothing)
  if date !== nothing
    deletion_date = min(deletion_date, date)
  end
  return repair_article_deletion_date(deletion_date, tm)
end


table_of_content_structure(table_of_content::RootTableOfContent) = table_of_content.textelr["STRUCT"]

table_of_content_structure(table_of_content::TableOfContent) = table_of_content.dict["STRUCTURE_TA"]


table_of_content_title(table_of_content::RootTableOfContent) = table_of_content.texte_version["META"]["META_SPEC"][
  "META_TEXTE_VERSION"]["TITREFULL"]

table_of_content_title(table_of_content::TableOfContent) = table_of_content.dict["TITRE_TA"]


function transform_structure_to_articles_tree(changed_by_changer::Dict{Changer, Changed}, dir::String,
    table_of_content::AbstractTableOfContent)
  structure = table_of_content_structure(table_of_content)

  for lien_section_ta in get(structure, "LIEN_SECTION_TA", Dict{String, Any}[])
    section_ta_file_path = joinpath(dir, "section_ta" * lien_section_ta["@url"])
    section_ta_xml_document = parse_file(section_ta_file_path)
    section_ta = Convertible(parse_xml_element(root(section_ta_xml_document))) |> pipe(
      element_to_section_ta,
      require,
    ) |> to_value
    child_table_of_content = TableOfContent(table_of_content, section_ta)
    transform_structure_to_articles_tree(changed_by_changer, dir, child_table_of_content)
  end

  for lien_article in get(structure, "LIEN_ART", Dict{String, Any}[])
    article = load_article(dir, lien_article["@id"])
    meta_article = article["META"]["META_SPEC"]["META_ARTICLE"]
    try
      article_object = Article(table_of_content, article)
      liens = get(article["LIENS"], "LIEN", Dict{String, Any}[])
      commit_liens = filter(liens) do lien
        if get(lien, "@datesignatexte", nothing) === nothing
          return false
        end
        if lien["@typelien"] in ("CITATION", "CREATION", "MODIFICATION") ||
            lien["@sens"] == "cible" && lien["@typelien"] == "TXT_SOURCE" ||
            lien["@sens"] == "source" && lien["@typelien"] == "SPEC_APPLI"
          return false
        end
        # if lien["@sens"] == "cible" && lien["@typelien"] == "MODIFIE"
        # if lien["@sens"] == "source" && lien["@typelien"] == "ABROGATION"
        return true
      end

      creation_date = nothing
      creation_message = nothing
      deletion_date = nothing
      deletion_message = nothing
      for lien in commit_liens
        if lien["@sens"] == "cible" && lien["@typelien"] == "ABROGATION"
          @assert(lien["@datesignatexte"] + Day(1) <= meta_article["DATE_FIN"] <= lien["@datesignatexte"] + Day(100),
            "Unexpected date $(lien["@datesignatexte"]) in :\n  $lien\n" *
            "  DATE_FIN article: $(meta_article["DATE_FIN"])")
          if deletion_date === nothing
            deletion_date = meta_article["DATE_FIN"]
            deletion_message = split(lien["^text"], " - ")[1]
          else
            @assert deletion_date == meta_article["DATE_FIN"]
            @assert(deletion_message == split(lien["^text"], " - ")[1],
              "Message \"$deletion_message\" differs from \"$(lien["^text"])\".")
          end
        elseif lien["@sens"] == "cible" && lien["@typelien"] == "MODIFIE"
          @assert(lien["@datesignatexte"] + Day(1) <= meta_article["DATE_DEBUT"] <= lien["@datesignatexte"] + Day(100),
            "Unexpected date $(lien["@datesignatexte"]) in :\n  $lien\n" *
            "  DATE_DEBUT article: $(meta_article["DATE_DEBUT"])")
          if creation_date === nothing
            creation_date = meta_article["DATE_DEBUT"]
            creation_message = split(lien["^text"], " - ")[1]
          else
            @assert creation_date == meta_article["DATE_DEBUT"]
            @assert(creation_message == split(lien["^text"], " - ")[1],
              "Message \"$creation_message\" differs from \"$(lien["^text"])\".")
          end
        end
      end

      if creation_date === nothing
        # No link for article. Assume this is a creation.
        creation_date = meta_article["DATE_DEBUT"]
        creation_message = "Modification"
      end
      creation_date = repair_article_creation_date(creation_date, article["CONTEXTE"]["TEXTE"])
      changer = Changer(creation_date, creation_message)
      changed = get!(changed_by_changer, changer) do
        return Changed()
      end
      push!(changed.articles, article_object)

      if get(meta_article, "DATE_FIN", nothing) !== nothing
        if deletion_date === nothing
          # No link for article. Assume this is a deletion.
          deletion_date = meta_article["DATE_FIN"]
          deletion_message = "Modification"
        end
        delete_article = false
        etat = get(meta_article, "ETAT", "")
        if etat == "ABROGE"
          delete_article = true
        elseif etat == "MODIFIE"
          next_article = nothing
          for version in article["VERSIONS"]["VERSION"]
            for next_lien_article in get(version, "LIEN_ART", Dict{String, Any}[])
              if next_lien_article["@debut"] == deletion_date
                next_article = load_article(dir, next_lien_article["@id"])
                break
              end
            end
            if next_article !== nothing
              break
            end
          end
          if next_article !== nothing &&
              git_dir(article["CONTEXTE"]["TEXTE"]["TM"]) != git_dir(next_article["CONTEXTE"]["TEXTE"]["TM"])
            # Article has moved.
            delete_article = true
          end
        end
        if delete_article
          deletion_date = repair_article_deletion_date(deletion_date, article["CONTEXTE"]["TEXTE"])
          changer = Changer(deletion_date, deletion_message)
          changed = get!(changed_by_changer, changer) do
            return Changed()
          end
          push!(changed.deleted_articles, article_object)
        end
      end
    catch
      warn("An exception occured in article $(meta_article["NUM"]) [$(get(meta_article, "ETAT", "inconnu"))]:" *
        " $(article["META"]["META_COMMUN"]["ID"]).")
      rethrow()
    end
  end

  # return isempty(children) ? nothing: Section(title, children)
end
