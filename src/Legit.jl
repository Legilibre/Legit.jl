# Legit.jl -- Convert French law in LEGI format to Git & Markdown
# By: Emmanuel Raviart <emmanuel.raviart@data.gouv.fr>
#
# Copyright (C) 2015 Etalab
# https://github.com/etalab/Legit.jl
#
# The GitLegistique.jl package is licensed under the MIT "Expat" License.


module Legit


import Base: hash, isequal, isless

using ArgParse
using Biryani
using Biryani.DatesConverters
using Compat
using Dates: Date, DateTime, datetime2unix, Day
using LibGit2
using LightXML
using Slugify


include("converters.jl")
include("articles.jl")


function main()
  args = parse_command_line()

  if !args["dry-run"]
    @assert splitext(args["repository"])[end] == ".git"
    if ispath(args["repository"])
      @assert isdir(args["repository"])
      @assert iswritable(args["repository"])
    else
      mkpath(args["repository"])
    end
    repository = init_repo(args["repository"]; bare = true)
  end

  version_dir = joinpath(args["dir"], "texte", "version")
  version_filenames = readdir(version_dir)
  @assert length(version_filenames) == 1 "Directory $version_dir contains more than 1 file: $version_filenames."
  version_filename = version_filenames[1]
  version_xml_document = parse_file(joinpath(version_dir, version_filename))
  texte_version = Convertible(parse_xml_element(root(version_xml_document))) |> pipe(
    element_to_texte_version,
    require,
  ) |> to_value

  struct_dir = joinpath(args["dir"], "texte", "struct")
  struct_filenames = readdir(struct_dir)
  @assert length(struct_filenames) == 1 "Directory $struct_dir contains more than 1 file: $struct_filenames."
  struct_filename = struct_filenames[1]
  @assert(version_filename == struct_filename,
    "Filenames for struct and version differ: $struct_filename != $version_filename.")
  struct_xml_document = parse_file(joinpath(struct_dir, struct_filename))
  textelr = Convertible(parse_xml_element(root(struct_xml_document))) |> pipe(
    element_to_textelr,
    require,
  ) |> to_value

  # articles_tree = transform_structure_to_articles_tree(changed_by_changer, args["dir"], textelr["STRUCT"],
  #   texte_version["META"]["META_SPEC"]["META_TEXTE_VERSION"]["TITREFULL"])
  # if get(texte_version, "VISAS", nothing) != nothing
  #   unshift!(articles_tree.children, NonArticle("", texte_version["VISAS"]["CONTENU"]))
  # end
  # if get(texte_version, "SIGNATAIRES", nothing) != nothing
  #   push!(articles_tree.children, NonArticle("", texte_version["SIGNATAIRES"]["CONTENU"]))
  # end
  # print(all_in_one_commonmark(articles_tree))

  changed_by_changer = @compat Dict{Changer, Changed}()
  root_table_of_content = RootTableOfContent(texte_version, textelr)
  transform_structure_to_articles_tree(changed_by_changer, args["dir"], root_table_of_content)
  changers = sort(collect(keys(changed_by_changer)))

  if !args["dry-run"]
    latest_commit = nothing
    root_tree = nothing
    for changer in changers
      epoch = int64(datetime2unix(DateTime(changer.date)))
      time_offset = 0
      author_signature = Signature("République française", "info@data.gouv.fr", epoch, time_offset)
      committer_signature = author_signature
      changed = changed_by_changer[changer]

      tree_builder_by_git_dir_names = @compat Dict{Tuple, GitTreeBuilder}()
      for article in changed.articles
        blob = blob_from_buffer(repository, all_in_one_commonmark(article))
        git_dir_names = tuple(split(section_git_dir(article), '/')...)
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
        insert!(tree_builder, section_filename(article), Oid(blob), int(0o100644))  # FILEMODE_BLOB
      end

      for article in changed.deleted_articles
        git_dir_names = tuple(split(section_git_dir(article), '/')...)
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
        delete!(tree_builder, section_filename(article))
      end

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
          tree_oid = length(tree_builder) == 0 ? nothing : write!(tree_builder)
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

      root_tree = lookup_tree(repository, root_tree_oid)
      latest_commit_oid = commit(repository, "HEAD", changer.message, author_signature, committer_signature, root_tree,
        (latest_commit === nothing ? [] : [latest_commit])...)
      latest_commit = lookup_commit(repository, latest_commit_oid)
    end
  end
end


function parse_command_line()
  arg_parse_settings = ArgParseSettings()
  @add_arg_table arg_parse_settings begin
    "--verbose", "-v"
      action = :store_true
      help = "increase output verbosity"
    "--dry-run", "-d"
      action = :store_true
      help = "don't write anything"
    "dir"
      help = "path of LEGI dir containing a law"
      required = true
    "repository"
      help = "path of Git repository to create"
      required = true
  end
  return parse_args(arg_parse_settings)
end


main()


end # module
