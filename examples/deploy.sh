#!/usr/bin/env bash
set -euo pipefail

LOG=/tmp/wp_setup.log
exec > >(tee -a "$LOG") 2>&1

on_err() {
  echo
  echo "❌ Fout opgetreden. Laatste 50 regels console-output:"
  tail -n 50 "$LOG" || true
}
trap on_err ERR

# --- CONFIG ---
WP="/var/www/html/wordpress"
ZIP="/home/wpbot/site.zip"
RAR="/home/wpbot/seera.framer.website.rar"

# --- PREP ---
if [ ! -f "$ZIP" ]; then
  if [ -f "$RAR" ]; then
    echo "No site.zip found. Converting RAR -> ZIP…"
    sudo apt-get update -y
    if ! command -v unar >/dev/null 2>&1; then
      sudo apt-get install -y unar || true
    fi
    if ! command -v unar >/dev/null 2>&1 && ! command -v unrar >/dev/null 2>&1; then
      sudo apt-get install -y unrar || sudo apt-get install -y unrar-free || true
    fi
    TMPDIR="$(mktemp -d)"
    if command -v unar >/dev/null 2>&1; then
      unar -o "$TMPDIR" "$RAR"
    else
      unrar x -o+ "$RAR" "$TMPDIR/"
    fi
    (cd "$TMPDIR" && zip -r "$ZIP" .)
    rm -rf "$TMPDIR"
    echo "Created $ZIP"
  else
    echo "⚠️ Geen $ZIP en ook geen $RAR gevonden. Upload eerst je site-archief."
    exit 1
  fi
fi

TD="$WP/wp-content/themes/gen-html"

sudo apt-get update -y
sudo apt-get install -y unzip

mkdir -p "$TD/assets/css" "$TD/assets/js" "$TD/assets/html/site"

if [ ! -f "$TD/style.css" ]; then
  cat > "$TD/style.css" <<EOF
/*
Theme Name: Gennaro HTML Bridge
Theme URI: https://gennaro.two-hosting.nl
Author: Touch by Gennaro
Version: 1.0.0
*/
body { margin:0; }
EOF
fi

if [ ! -f "$TD/functions.php" ]; then
  cat > "$TD/functions.php" <<'PHP'
<?php
add_action("wp_enqueue_scripts", function () {
  wp_enqueue_style("theme-style", get_stylesheet_uri(), [], null);
  $css = get_stylesheet_directory() . "/assets/css/site.css";
  if (file_exists($css)) {
    wp_enqueue_style("site-css", get_stylesheet_directory_uri() . "/assets/css/site.css", [], null);
  }
  $js = get_stylesheet_directory() . "/assets/js/site.js";
  if (file_exists($js)) {
    wp_enqueue_script("site-js", get_stylesheet_directory_uri() . "/assets/js/site.js", [], null, true);
  }
});
PHP
fi

cat > "$TD/header.php" <<'PHP'
<!doctype html>
<html <?php language_attributes(); ?>>
<head>
<meta charset="<?php bloginfo("charset"); ?>">
<meta name="viewport" content="width=device-width, initial-scale=1">
<?php wp_head(); ?>
<?php if ( is_front_page() ) : ?>
<base href="<?php echo esc_url( get_stylesheet_directory_uri() ); ?>/assets/html/site/">
<?php endif; ?>
</head>
<body <?php body_class(); ?>>
PHP

cat > "$TD/footer.php" <<'PHP'
<?php wp_footer(); ?>
</body>
</html>
PHP

# index.php (fallback vereist door WordPress)
if [ ! -f "$TD/index.php" ]; then
  cat > "$TD/index.php" <<'PHP'
<?php get_header(); ?>
<main id="primary">
<?php
if ( is_front_page() ) {
  echo do_shortcode('[embed_html file="site/index.html"]');
} else {
  if ( have_posts() ) { while ( have_posts() ) { the_post(); the_content(); } }
  else { echo "<p>No content.</p>"; }
}
?>
</main>
<?php get_footer(); ?>
PHP
fi


cat > "$TD/front-page.php" <<'PHP'
<?php get_header(); ?>
<?php echo do_shortcode("[embed_html file=\"site/index.html\"]"); ?>
<?php get_footer(); ?>
PHP

mkdir -p "$WP/wp-content/mu-plugins"
cat > "$WP/wp-content/mu-plugins/embed-html.php" <<'PHP'
<?php
/*
Plugin Name: Embed HTML from Theme
Description: Shortcode [embed_html file="path/to/file.html"] toont raw HTML uit /assets/html in het actieve theme.
*/
add_shortcode("embed_html", function ($atts) {
  $a = shortcode_atts(["file" => ""], $atts);
  $file = preg_replace("/[^A-Za-z0-9_\\-\\/\\.]/", "", $a["file"]);
  if (!$file) return "";
  $path = get_stylesheet_directory() . "/assets/html/" . ltrim($file, "/");
  if (!file_exists($path)) return "<!-- embed_html: file not found -->";
  return file_get_contents($path);
});
PHP

unzip -o /home/wpbot/site.zip -d "$TD/assets/html/site" >/dev/null 2>&1 || true

sudo chown -R www-data:www-data "$TD" "$WP/wp-content/mu-plugins"

sudo -u www-data -H -- wp --path="$WP" theme activate gen-html
sudo -u www-data -H -- wp --path="$WP" option update blogname "Touch by Gennaro"
sudo -u www-data -H -- wp --path="$WP" option update blogdescription "Portfolio"

HOME_ID=$(sudo -u www-data -H -- wp --path="$WP" post list --post_type=page --name=home --field=ID || true)
if [ -z "$HOME_ID" ]; then
  HOME_ID=$(sudo -u www-data -H -- wp --path="$WP" post create --post_type=page --post_title="Home" --post_status=publish --porcelain)
fi
sudo -u www-data -H -- wp --path="$WP" option update show_on_front page
sudo -u www-data -H -- wp --path="$WP" option update page_on_front "$HOME_ID"

sudo -u www-data -H -- wp --path="$WP" rewrite structure "/%postname%/" --hard
sudo -u www-data -H -- wp --path="$WP" rewrite flush --hard

MENU_ID=$(sudo -u www-data -H -- wp --path="$WP" menu list --fields=term_id --format=ids | head -n1)
if [ -z "$MENU_ID" ]; then
  sudo -u www-data -H -- wp --path="$WP" menu create "Hoofdmenu"
  MENU_ID=$(sudo -u www-data -H -- wp --path="$WP" menu list --fields=term_id --format=ids | head -n1)
fi
for SLUG in home over contact; do
  PID=$(sudo -u www-data -H -- wp --path="$WP" post list --post_type=page --name=$SLUG --field=ID || true)
  if [ -z "$PID" ] && [ "$SLUG" != "home" ]; then
    TITLE=$( [ "$SLUG" = "over" ] && echo "Over" || echo "Contact" )
    PID=$(sudo -u www-data -H -- wp --path="$WP" post create --post_type=page --post_title="$TITLE" --post_status=publish --porcelain)
  fi
  [ -n "$PID" ] && sudo -u www-data -H -- wp --path="$WP" menu item add-post "$MENU_ID" "$PID" >/dev/null 2>&1 || true
done
sudo -u www-data -H -- wp --path="$WP" menu location assign "$MENU_ID" primary || true

sudo -u www-data -H -- wp --path="$WP" plugin install cache-enabler --activate >/dev/null 2>&1 || true

echo "✅ Gereed."
