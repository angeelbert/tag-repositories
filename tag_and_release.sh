#!/bin/bash

# tag_and_release.sh

# Función para etiquetar y lanzar un solo repositorio
tag_and_release_repo() {
  repo_url="$1"
  tag_name="$2"

  echo "Tagging and releasing in $repo_url"
  repo_name=$(basename "$(echo "$repo_url" | sed 's/\.git$//')" | tr -d '\r')
  authenticated_repo_url="https://${GH_TOKEN}@${repo_url#https://}"

  if git ls-remote --tags "$repo_url" | grep -q "refs/tags/$tag_name"; then
    echo "Tag $tag_name already exists in $repo_url. Skipping tagging."
  else
    if [ -d "$repo_name" ]; then
      echo "Repository directory already exists. Skipping cloning."
    else
      git clone "$authenticated_repo_url" "$repo_name" || { echo "Failed to clone repository: $repo_url"; exit 1; }
    fi
    cd "$repo_name" || { echo "Failed to change directory to repository: $repo_name"; exit 1; }
    git config user.name "github-actions[bot]"
    git config user.email "github-actions[bot]@users.noreply.github.com"
    git tag -a "$tag_name" -m "Tagging version $tag_name"
    git push "$authenticated_repo_url" --tags || { echo "Failed to push tags to repository: $repo_url"; exit 1; }
    cd ..
  fi

  repo_api_url="https://api.github.com/repos/${repo_url#https://github.com/}/releases"
  release_response=$(curl -X POST \
    -H "Authorization: token $GH_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "$repo_api_url" \
    -d @- <<EOF
{
  "tag_name": "$tag_name",
  "target_commitish": "main",
  "name": "Release $tag_name",
  "body": "### [$tag_name]($repo_url/compare/v${tag_name}...v$tag_name) (2024-05-24)",
  "draft": false,
  "prerelease": false
}
EOF
  )
  if echo "$release_response" | grep -q 'created_at'; then
    echo "Release created successfully for $repo_url"
  else
    if echo "$release_response" | grep -q 'already_exists'; then
      echo "Release for tag $tag_name already exists. Skipping release creation."
    else
      echo "Failed to create release for $repo_url: $release_response"
    fi
  fi
}

# Etiquetar y lanzar repositorios
while IFS= read -r repo_url; do
  tag_and_release_repo "$(echo "$repo_url" | tr -d '\r')" "$1"
done < repos.txt

# Etiquetar archivos en las rutas proporcionadas
if [ -f "files.txt" ]; then
  while IFS= read -r file_path; do
    echo "Tagging file: $file_path"
    file_name=$(basename "$file_path" | tr -d '\r')
    tag_name="$1"

    # Verificar si ya estamos en un repositorio antes de intentar etiquetar el archivo
    if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
      # Asegurarse de que el archivo esté versionado y tiene cambios
      git add "$file_path" || { echo "Failed to add file $file_path"; continue; }
      
      # Comprobar si hay cambios para comitear
      if git diff-index --quiet HEAD -- "$file_path"; then
        echo "No changes to commit for $file_path"
      else
        git commit -m "Tagging file $file_path with tag $tag_name" || { echo "No changes to commit for $file_path"; continue; }
      fi

      # Forzar la creación de la etiqueta
      git tag -a "$tag_name" -m "Tagging file $file_path with tag $tag_name" --force || { echo "Failed to tag file $file_path with tag $tag_name"; continue; }
      git push origin "$tag_name" --force || { echo "Failed to push tag $tag_name for file $file_path"; continue; }
      echo "Tagged file $file_path with tag $tag_name"
    else
      echo "Not inside a git repository. Skipping file tagging."
    fi
  done < files.txt
else
  echo "No files.txt found. Skipping file tagging."
fi