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
import DataStructures: OrderedDict
using Dates: Date, DateTime, datetime2unix, Day
using LibGit2
using LightXML
using Slugify


include("converters.jl")
include("articles.jl")


function main()
  args = parse_command_line()
  mode = args["mode"]

  if !args["dry-run"]
    @assert splitext(args["repository"])[end] == ".git"
    if ispath(args["repository"])
      @assert isdir(args["repository"])
      @assert iswritable(args["repository"])
      rm(args["repository"]; recursive = true)
    end
    mkpath(args["repository"])
    repository = init_repo(args["repository"]; bare = true)
  else
    repository = nothing
  end

  latest_commit = nothing
  node_by_nature = @compat Dict{String, Nature}()
  root_section = Section()
  root_tree = nothing
  for (document_index, document_dir) in enumerate(@task walk_documents_dir(args["legi_dir"]))
    # document_index < 96802 && continue  # TODO: Remove.
println()
println()
println("=============================================================================================================")
println(document_index, " / ", document_dir)

    version_dir = joinpath(document_dir, "texte", "version")
    version_filenames = sort(readdir(version_dir))
    struct_dir = joinpath(document_dir, "texte", "struct")
    struct_filenames = sort(readdir(struct_dir))
    @assert(length(struct_filenames) == length(version_filenames),
      "Directory $struct_dir doesn't contain the same number of files as directory: $struct_filenames.")

    articles_by_id = @compat Dict{String, Vector{Article}}()  # Articles are sorted by start date for each ID.
    changed_by_message_by_date = @compat Dict{Date, OrderedDict{String, Changed}}()
    for (version_filename, struct_filename) in zip(version_filenames, struct_filenames)
      version_xml_document = parse_file(joinpath(version_dir, version_filename))
      texte_version = Convertible(parse_xml_element(root(version_xml_document))) |> pipe(
        element_to_texte_version,
        require,
      ) |> to_value

      @assert(version_filename == struct_filename,
        "Filenames for struct and version differ: $struct_filename != $version_filename.")
      struct_xml_document = parse_file(joinpath(struct_dir, struct_filename))
      textelr = Convertible(parse_xml_element(root(struct_xml_document))) |> pipe(
        element_to_textelr,
        require,
      ) |> to_value

      # articles_tree = parse_structure(changed_by_changer, document_dir, textelr["STRUCT"],
      #   texte_version["META"]["META_SPEC"]["META_TEXTE_VERSION"]["TITREFULL"])
      # if get(texte_version, "VISAS", nothing) != nothing
      #   unshift!(articles_tree.children, NonArticle("", texte_version["VISAS"]["CONTENU"]))
      # end
      # if get(texte_version, "SIGNATAIRES", nothing) != nothing
      #   push!(articles_tree.children, NonArticle("", texte_version["SIGNATAIRES"]["CONTENU"]))
      # end
      # print(commonmark(articles_tree, mode))
      nature = get(texte_version["META"]["META_COMMUN"], "NATURE", "nature_inconnue")
      nature_node = get!(node_by_nature, nature) do
        return Nature(nature)
      end
      document = Document(nature_node, texte_version, textelr)
@show node_title(document)
println("=============================================================================================================")
println()
      parse_structure(articles_by_id, changed_by_message_by_date, document_dir, document)
    end
    link_articles(articles_by_id)
    dates = sort(collect(keys(changed_by_message_by_date)))

    if !args["dry-run"]
      for date in dates
        # upserted_git_files_path = Set{String}()
        # for (message, changed) in changed_by_message_by_date[date]
        #   for article in changed.articles
        #     push!(upserted_git_files_path, node_git_file_path(article))
        #   end
        # end

        for (message, changed) in changed_by_message_by_date[date]
println("-------------------------------------------------------------------------------------------------------------")
println("$date $message")
          epoch = int64(datetime2unix(DateTime(date)))
          time_offset = 0
          author_signature = Signature("République française", "info@data.gouv.fr", epoch, time_offset)
          committer_signature = author_signature
          commit_needed = false

          # Update sections tree.
          for article in changed.articles
println("Upserted: ", string(node_id(article), " ", node_git_file_path(article)))
            nodes = Node[]
            container = article.container
            while true
              unshift!(nodes, container)
              if isa(container, Nature)
                break
              end
              container = container.container
            end
            section = root_section
            for node in nodes
              section = get!(section.child_by_name, node_name(node)) do
                return Section()
              end
              section.sortable_title = node_sortable_title(node)
              section.title = node_title(node)
            end
            section.child_by_name[node_name(article)] = article
          end
          deleted_articles = Article[]
          for article in changed.deleted_articles
            next_version = get(article.next_version, article)
            if next_version != article && node_git_file_path(article) == node_git_file_path(next_version)
            # if node_git_file_path(article) in upserted_git_files_path
              # Article is neither deleted nor moved => Keep it unchanged.
              continue
            end
println("Deleted: ", string(node_id(article), " ", node_git_file_path(article)))
            nodes = Node[]
            container = article
            while true
              unshift!(nodes, container)
              if isa(container, Nature)
                break
              end
              container = container.container
            end
            section = root_section
            sections = Node[]
            for node in nodes
              push!(sections, section)
              section = get(section.child_by_name, node_name(node), nothing)
              if section === nothing
                warn("Unknown sub-section $(node_name(node))")
                sections = Node[]
                break
              end
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

          if mode == "single-page"
            root_tree_builder = GitTreeBuilder(repository, root_tree)
            single_section = first(first(root_section.child_by_name)[2].child_by_name)[2]
            single_section_filename = node_filename(single_section)
            blob = blob_from_buffer(repository, commonmark(single_section, mode))
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
              blob = blob_from_buffer(repository, commonmark(article, mode))
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
                  if length(tree_builder) == 0 || mode in ("deep-readme", "flat-readme") && length(tree_builder) == 1 &&
                      tree_builder["README.md"] !== nothing
                    tree_oid = nothing
                  else
                    if mode in ("deep-readme", "flat-readme")
                      section = root_section
                      for dir_name in git_dir_names
                        section = section.child_by_name[dir_name]
                      end
                      blob = blob_from_buffer(repository, commonmark(section, mode))
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

    # document_index >= 12 && break  # TODO: Remove.
  end
end


function parse_command_line()
  arg_parse_settings = ArgParseSettings()
  @add_arg_table arg_parse_settings begin
    "--dry-run", "-d"
      action = :store_true
      help = "don't write anything"
    "--mode", "-m"
      default = "flat-readme"
      help = "mode for generated tree of files (deep-readme, flat-readme, no-readme, single-page)"
      range_tester = value -> value in ("deep-readme", "flat-readme", "no-readme", "single-page")
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


main()


end # module
