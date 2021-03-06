# Legit.jl -- Convert French law in LEGI format to Git & Markdown
# By: Emmanuel Raviart <emmanuel.raviart@data.gouv.fr>
#
# Copyright (C) 2015 Etalab
# https://github.com/etalab/Legit.jl
#
# The Legit.jl package is licensed under the MIT "Expat" License.


module Legit


using ArgParse
using Biryani
using Biryani.DatesConverters
using Compat
using Dates: Date, DateTime, datetime2unix, Day, year
using LibGit2
using LightXML
import Slugify


include("converters.jl")
include("articles.jl")


function main()
  args = parse_command_line()
  mode = args["mode"]
  readme_mode = args["readme"]

  @assert splitext(args["repository"])[end] == ".git"
  if ispath(args["repository"])
    @assert isdir(args["repository"])
    @assert iswritable(args["repository"])
    if args["erase"]
      rm(args["repository"]; recursive = true)
    end
  end
  if ispath(args["repository"])
    repository = repo_discover(args["repository"])
    head_reference = head(repository)
    latest_commit_oid = target(head_reference)
    latest_commit = lookup_commit(repository, latest_commit_oid)
    root_tree = GitTree(latest_commit)
  else
    mkpath(args["repository"])
    repository = init_repo(args["repository"]; bare = true)
    latest_commit = nothing
    root_tree = nothing
  end

  if mode == "all"
    documents_dir_walker = @task walk_documents_dir(joinpath(args["legi_dir"], "global"))
    node_by_nature = @compat Dict{String, SimpleNode}()
    node_by_year_by_container = @compat Dict{SimpleNode, Dict{String, SimpleNode}}()
    root_title = "Lois et règlements français"
  elseif mode == "codes"
    documents_dir_walker = @task walk_documents_dir(
      joinpath(args["legi_dir"], "global", "code_et_TNC_en_vigueur", "code_en_vigueur"),
      joinpath(args["legi_dir"], "global", "code_et_TNC_non_vigueur", "code_non_vigueur"),
    )
    root_title = "Codes juridiques français"
  else
    @assert mode == "non-codes"
    documents_dir_walker = @task walk_documents_dir(
      joinpath(args["legi_dir"], "global", "code_et_TNC_en_vigueur", "TNC_en_vigueur"),
      joinpath(args["legi_dir"], "global", "code_et_TNC_non_vigueur", "TNC_non_vigueur"),
    )
    node_by_nature = @compat Dict{String, SimpleNode}()
    node_by_year_by_container = @compat Dict{SimpleNode, Dict{String, SimpleNode}}()
    root_title = "Lois non codifiées et règlements français"
  end
  codes_en_vigueur_node = nothing
  codes_non_vigueur_node = nothing
  root_node = RootNode(root_title)
  skip_documents = args["start"] !== nothing
  for (document_index, document_dir) in enumerate(documents_dir_walker)
    if args["only"] !== nothing && basename(document_dir) != args["only"]
      continue
    end
    if skip_documents
      document_cid = basename(document_dir)
      if document_cid == args["start"]
        skip_documents = false
      else
        continue
      end
    end

println()
println()
println("=============================================================================================================")
println(document_index, " / ", document_dir)

    root_section = root_tree === nothing ?
      Section(root_node.title) :
      parse_section_commonmark(repository, entry_bypath(root_tree, "README.md"), root_node.title)

    version_dir = joinpath(document_dir, "texte", "version")
    version_filenames = sort(readdir(version_dir))
    struct_dir = joinpath(document_dir, "texte", "struct")
    struct_filenames = sort(readdir(struct_dir))
    @assert(length(struct_filenames) == length(version_filenames),
      "Directory $struct_dir doesn't contain the same number of files as directory: $struct_filenames.")

    articles_by_id = @compat Dict{String, Vector{Article}}()  # Articles are sorted by start date for each ID.
    changed_by_message_by_date = @compat Dict{Date, Dict{String, Changed}}()
    notes = nothing
    signataires = nothing
    visas = nothing
    for (version_filename, struct_filename) in zip(version_filenames, struct_filenames)
      version_xml_document = parse_file(joinpath(version_dir, version_filename))
      texte_version = Convertible(parse_xml_element(root(version_xml_document))) |> pipe(
        element_to_texte_version,
        require,
      ) |> to_value
      # free(version_xml_document)

      @assert(version_filename == struct_filename,
        "Filenames for struct and version differ: $struct_filename != $version_filename.")
      struct_xml_document = parse_file(joinpath(struct_dir, struct_filename))
      textelr = Convertible(parse_xml_element(root(struct_xml_document))) |> pipe(
        element_to_textelr,
        require,
      ) |> to_value
      # free(struct_xml_document)

      if mode == "all"
        nature = get(texte_version["META"]["META_COMMUN"], "NATURE", "nature_inconnue")
        document_container = get!(node_by_nature, nature) do
          return SimpleNode(root_node, nature)
        end
      elseif mode == "codes"
        document_container = root_node
      else
        @assert mode == "non-codes"
        nature = get(texte_version["META"]["META_COMMUN"], "NATURE", "nature_inconnue")
        document_container = get!(node_by_nature, nature) do
          return SimpleNode(root_node, nature)
        end
      end
      if contains(document_dir, "code_en_vigueur")
        if codes_en_vigueur_node === nothing
          codes_en_vigueur_node = SimpleNode(document_container, "Codes en vigueur")
        end
        document_container = codes_en_vigueur_node
      elseif contains(document_dir, "code_non_vigueur")
        if codes_non_vigueur_node === nothing
          codes_non_vigueur_node = SimpleNode(document_container, "Codes non en vigueur")
        end
        document_container = codes_non_vigueur_node
      else
        node_by_year = get!(node_by_year_by_container, document_container) do
          return @compat Dict{String, SimpleNode}()
        end
        start_date = get(texte_version["META"]["META_SPEC"]["META_TEXTE_VERSION"], "DATE_DEBUT", nothing)
        year_text = start_date === nothing ? "Année inconnue" : string(year(start_date))
        document_container = get!(node_by_year, year_text) do
          return SimpleNode(document_container, year_text)
        end
      end
      document = Document(document_container, texte_version, textelr)
@show node_title(document)
println("=============================================================================================================")
println()

      if notes === nothing
        notes_dict = get(document.texte_version, "NOTA", nothing)
        if notes_dict !== nothing
          notes = NonArticle(document, "notes", "Nota", notes_dict["CONTENU"])
        end
      end
      if signataires === nothing
        signataires_dict = get(document.texte_version, "SIGNATAIRES", nothing)
        if signataires_dict !== nothing
          signataires = NonArticle(document, "signataires", "", signataires_dict["CONTENU"])
        end
      end
      if visas === nothing
        visas_dict = get(document.texte_version, "VISAS", nothing)
        if visas_dict !== nothing
          visas = NonArticle(document, "visas", "", visas_dict["CONTENU"])
        end
      end

      parse_structure(document, articles_by_id, changed_by_message_by_date, document_dir)
    end
    link_articles(articles_by_id)

    for (date_index, date) in enumerate(sort(collect(keys(changed_by_message_by_date))))
      if args["last-date"] !== nothing && date > Date(args["last-date"])
        continue
      end
      changed_by_message = changed_by_message_by_date[date]
      for (message_index, message) in enumerate(sort(collect(keys(changed_by_message))))
        changed = changed_by_message[message]
println("-------------------------------------------------------------------------------------------------------------")
println("$date $message")
        epoch = int64(datetime2unix(DateTime(date)))
        if args["date"]
          # Modify dates before 1970-02-01 (epoch = 2678340) to ensure that they are >= 1970-01-01 (epoch = 0).
          if epoch < 2678340  # = 31 * 24 * 60 * 60 = 1970-02-01
            epoch /= 24 * 60 * 60  # Days become seconds
            epoch += 2678340 - 31  # 31 = days of 1970-01
          end
        end
        time_offset = 0
        author_signature = Signature("République française", "gitloi@data.gouv.fr", epoch, time_offset)
        committer_signature = author_signature
        commit_needed = false

        if date_index == 1 && message_index == 1
          if visas !== nothing
            unshift!(changed.articles, visas)
          end
          if signataires !== nothing
            push!(changed.articles, signataires)
          end
          if notes !== nothing
            push!(changed.articles, notes)
          end
        end

        # Update sections tree.
        for article in changed.articles
if isa(article, Article)
  println("Upserted: ", node_id(article), " ", node_git_file_path(article), ".")
else
  println("Upserted: non article ", node_git_file_path(article), ".")
end
          nodes = Node[]
          container = article.container
          while true
            unshift!(nodes, container)
            container = container.container
            if isa(container, RootNode)
              break
            end
          end
          section = root_section
          section_names = String[]
          for node in nodes
            dir_name = node_dir_name(node)
            push!(section_names, dir_name)
            child_section = get!(section.child_by_name, dir_name) do
              return Section()
            end
            if isa(child_section, UnparsedSection)
              child_section = parse_section_commonmark(repository,
                entry_bypath(root_tree, string(join(section_names, '/'), '/', "README.md")), child_section.short_title)
              section.child_by_name[dir_name] = child_section
            end
            section = child_section
            section.short_title = node_short_title(node)
            section.sortable_title = node_sortable_title(node)
            section.title = node_title(node)
          end
          section.child_by_name[node_name(article)] = article
        end
        deleted_articles = Article[]
        for article in changed.deleted_articles
          next_version = get(article.next_version, article)
          if next_version != article && node_git_file_path(article) == node_git_file_path(next_version)
            # Article is neither deleted nor moved => Keep it unchanged.
            continue
          end
println("Deleted: ", string(node_id(article), " ", node_git_file_path(article)))
          nodes = Node[]
          container = article
          while true
            unshift!(nodes, container)
            container = container.container
            if isa(container, RootNode)
              break
            end
          end
          section = root_section
          section_names = String[]
          sections = Node[]
          for node in nodes
            push!(sections, section)
            name = node_name(node)
            push!(section_names, name)
            child_section = get(section.child_by_name, name, nothing)
            if child_section === nothing
              warn("Unknown sub-section $(node_name(node))")
              sections = Node[]
              break
            elseif isa(child_section, UnparsedSection)
              child_section = parse_section_commonmark(repository,
                entry_bypath(root_tree, string(join(section_names, '/'), '/', "README.md")), child_section.short_title)
              section.child_by_name[name] = child_section
            end
            section = child_section
          end
          if !isempty(sections)
            push!(deleted_articles, article)
            for (node, section) in zip(reverse(nodes), reverse(sections))
              delete!(section.child_by_name, node_name(node))
              if !isempty(section.child_by_name)
                break
              end
            end
          end
        end

        if readme_mode == "single-page"
          root_tree_builder = GitTreeBuilder(repository, root_tree)
          single_section = first(first(root_section.child_by_name)[2].child_by_name)[2]
          single_section_filename = node_filename(single_section)
          blob = blob_from_buffer(repository, commonmark(single_section, readme_mode))
          blob_id = Oid(blob)
          entry = root_tree_builder[single_section_filename]
          if entry === nothing || Oid(entry) != blob_id
            insert!(root_tree_builder, single_section_filename, blob_id, int(0o100644))  # FILEMODE_BLOB
            commit_needed = true
            root_tree_oid = write!(root_tree_builder)
          end
        else
          tree_builder_by_git_dir_names = @compat Dict{Tuple, GitTreeBuilder}()

          for article in changed.articles
            git_dir_names = tuple(split(node_git_dir(article), '/')...)
            tree_builder = get!(tree_builder_by_git_dir_names, git_dir_names) do
              if root_tree === nothing
                latest_tree = nothing
              elseif isempty(git_dir_names)
                latest_tree = root_tree
              else
                entry = entry_bypath(root_tree, join(git_dir_names, '/'))
                latest_tree = entry === nothing ? nothing : lookup_tree(repository, Oid(entry))
              end
              return GitTreeBuilder(repository, latest_tree)
            end
            article_filename = node_filename(article)
            blob = blob_from_buffer(repository, commonmark(article, readme_mode))
            blob_id = Oid(blob)
            entry = tree_builder[article_filename]
            if entry === nothing || Oid(entry) != blob_id
              insert!(tree_builder, article_filename, blob_id, int(0o100644))  # FILEMODE_BLOB
              commit_needed = true
            end
          end

          for article in deleted_articles
            git_dir_names = tuple(split(node_git_dir(article), '/')...)
            tree_builder = get!(tree_builder_by_git_dir_names, git_dir_names) do
              if root_tree === nothing
                latest_tree = nothing
              elseif isempty(git_dir_names)
                latest_tree = root_tree
              else
                entry = entry_bypath(root_tree, join(git_dir_names, '/'))
                latest_tree = entry === nothing ? nothing : lookup_tree(repository, Oid(entry))
              end
              return GitTreeBuilder(repository, latest_tree)
            end
            article_filename = node_filename(article)
            entry = tree_builder[article_filename]
            if entry !== nothing
              delete!(tree_builder, article_filename)
              commit_needed = true
            end
          end

          if commit_needed
            root_tree_oid = nothing
            while !isempty(tree_builder_by_git_dir_names)
              git_dirs_names_to_build = Set(keys(tree_builder_by_git_dir_names))
              for (git_dir_names, tree_builder) in tree_builder_by_git_dir_names
                while !isempty(git_dir_names)
                  git_dir_names = git_dir_names[1 : end - 1]
                  pop!(git_dirs_names_to_build, git_dir_names, nothing)
                end
              end
              for git_dir_names in git_dirs_names_to_build
                tree_builder = pop!(tree_builder_by_git_dir_names, git_dir_names)
                if length(tree_builder) == 0 || readme_mode in ("deep", "flat") && length(tree_builder) == 1 &&
                    tree_builder["README.md"] !== nothing
                  tree_oid = nothing
                else
                  if readme_mode in ("deep", "flat")
                    section = root_section
                    for dir_name in git_dir_names
                      section = section.child_by_name[dir_name]
                    end
                    blob = blob_from_buffer(repository, commonmark(section, readme_mode))
                    insert!(tree_builder, "README.md", Oid(blob), int(0o100644))  # FILEMODE_BLOB
                  end
                  tree_oid = write!(tree_builder)
                end
                if isempty(git_dir_names)
                  root_tree_oid = tree_oid
                else
                  dir_name = git_dir_names[end]
                  git_dir_names = git_dir_names[1 : end - 1]
                  @assert !(git_dir_names in git_dirs_names_to_build)
                  tree_builder = get!(tree_builder_by_git_dir_names, git_dir_names) do
                    if root_tree === nothing
                      latest_tree = nothing
                    elseif isempty(git_dir_names)
                      latest_tree = root_tree
                    else
                      entry = entry_bypath(root_tree, join(git_dir_names, '/'))
                      latest_tree = entry === nothing ? nothing : lookup_tree(repository, Oid(entry))
                    end
                    return GitTreeBuilder(repository, latest_tree)
                  end
                  if tree_oid === nothing
                    delete!(tree_builder, dir_name)
                  else
                    insert!(tree_builder, dir_name, tree_oid, int(0o40000))  # FILEMODE_TREE
                  end
                end
              end
            end
          end
        end

        if commit_needed
          root_tree = lookup_tree(repository, root_tree_oid)
          latest_commit_oid = commit(repository, "HEAD", message, author_signature, committer_signature,
            root_tree, (latest_commit === nothing ? [] : [latest_commit])...)
          latest_commit = lookup_commit(repository, latest_commit_oid)
        end
      end
    end
  end
end


function parse_command_line()
  arg_parse_settings = ArgParseSettings()
  @add_arg_table arg_parse_settings begin
    "--date", "-d"
      action = :store_true
      help = "modify commit dates before 1970-02-01 to ensure that they are after 1970-01-01"
    "--erase", "-e"
      action = :store_true
      help = "erase existing Git repository"
    "--last-date", "-l"
      help = "remove commits that are too much in the future (more than 25 years) for compatibility with GitLab"
      range_tester = value -> Convertible(value) |> iso8601_input_to_date |> require |> is_valid
    "--mode", "-m"
      default = "all"
      help = "mode for generated tree of files in Git repository (all, codes)"
      range_tester = value -> value in ("all", "codes", "non-codes")
    "--only", "-o"
      help = "CID of single LEGI document to parse"
      range_tester = value -> Convertible(value) |> validate_cid |> require |> is_valid
    "--readme", "-r"
      default = "flat"
      help = "mode for README file (deep, flat, none, single-page)"
      range_tester = value -> value in ("deep", "flat", "none", "single-page")
    "--start", "-s"
      help = "CID of first LEGI document to parse"
      range_tester = value -> Convertible(value) |> validate_cid |> require |> is_valid
    "--verbose", "-v"
      action = :store_true
      help = "increase output verbosity"
    "legi_dir"
      help = "path of LEGI dir"
      required = true
    "repository"
      help = "path of Git repository to create"
      required = true
  end
  return parse_args(arg_parse_settings)
end


function walk_documents_dir(dir::String)
  filenames = readdir(dir)
  is_texte_version = endswith(dir, joinpath("texte", "version"))
  texte_version_files_found = false
  for filename in filenames
    file_path = joinpath(dir, filename)
    if isdir(file_path)
      walk_documents_dir(file_path)
    elseif is_texte_version && isfile(file_path)
      texte_version_files_found = true
    end
  end
  if texte_version_files_found
    document_dir = dirname(dirname(dir))
    produce(document_dir)
  end
end

function walk_documents_dir(dirs::String...)
  for dir in dirs
    walk_documents_dir(dir)
  end
end


main()


end # module
