# Builds the static site into ./dist
#   Windows:  powershell -ExecutionPolicy Bypass -File build.ps1
#   GitHub:   pwsh ./build.ps1   (see .github/workflows/deploy.yml)
#
# All text lives in content/ (edited through Pages CMS, see .pages.yml):
#   content/settings.json        phone, email, photos, form key (shared)
#   content/<lang>/ui.json       menu, buttons, footer and other small texts
#   content/<lang>/<page>.json   one file per page
#   content/blog/<lang>/*.md     articles (front matter + Markdown body)
# This script holds only the HTML structure, so it stays plain ASCII.

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$dist = Join-Path $root 'dist'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$siteUrl = 'https://makrimargarita.gr'

$paths = @{
  el = @{ home = '/'; cv = '/viografiko/'; approach = '/proseggisi/'; services = '/ypiresies/'; blog = '/arthra/'; faq = '/syxnes-erotiseis/'; booking = '/rantevou/'; privacy = '/aporrito/' }
  en = @{ home = '/en/'; cv = '/en/about/'; approach = '/en/approach/'; services = '/en/services/'; blog = '/en/articles/'; faq = '/en/faq/'; booking = '/en/appointment/'; privacy = '/en/privacy/' }
}
$cultures = @{ el = 'el-GR'; en = 'en-GB' }

# ---------------------------------------------------------------- helpers

function Read-Json([string]$rel) {
  [IO.File]::ReadAllText((Join-Path $root $rel), $utf8) | ConvertFrom-Json
}

function E($s) { [System.Net.WebUtility]::HtmlEncode([string]$s) }

# Inline Markdown on one line of text: images, links, bold, italic, and
# [text in brackets] that is still to be written, shown highlighted.
function I($s) {
  # The online editor may write CommonMark escapes such as \[ or \*; read them as plain characters
  $s = [regex]::Replace([string]$s, '\\([\\`*_{}\[\]()#+\-.!>|~])', '$1')
  $s = E $s
  $s = [regex]::Replace($s, '&lt;br\s*/?&gt;', '<br>')
  $s = [regex]::Replace($s, '!\[([^\]]*)\]\(([^)\s]+)\)', '<img src="$2" alt="$1" loading="lazy">')
  $s = [regex]::Replace($s, '\[([^\]]+)\]\(([^)\s]+)\)', {
    param($m)
    $href = $m.Groups[2].Value
    $ext = if ($href -match '^https?://') { ' rel="noopener"' } else { '' }
    "<a href=`"$href`"$ext>$($m.Groups[1].Value)</a>"
  })
  $s = [regex]::Replace($s, '\[([^\]]+)\]', '<span class="todo">[$1]</span>')
  $s = [regex]::Replace($s, '(?<![\w.:"/>-])([\w.+-]+@(?:[\w-]+\.)+[a-zA-Z]{2,})', '<a href="mailto:$1">$1</a>')
  $s = [regex]::Replace($s, '\*\*(.+?)\*\*|__(.+?)__', { param($m) "<strong>$($m.Groups[1].Value)$($m.Groups[2].Value)</strong>" })
  $s = [regex]::Replace($s, '(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])', '<em>$1</em>')
  $s = [regex]::Replace($s, '(?<![\w])_(?!\s)(.+?)(?<!\s)_(?![\w])', '<em>$1</em>')
  $s
}

# Block Markdown: headings, paragraphs, lists, quotes, standalone images
function M($md) {
  $out = New-Object System.Collections.Generic.List[string]
  $para = New-Object System.Collections.Generic.List[string]
  $items = New-Object System.Collections.Generic.List[string]
  $quote = New-Object System.Collections.Generic.List[string]
  $script:listTag = 'ul'

  $flush = {
    if ($para.Count) { $out.Add('<p>' + (($para | ForEach-Object { I $_ }) -join ' ') + '</p>'); $para.Clear() }
    if ($items.Count) { $out.Add("<$script:listTag>" + (($items | ForEach-Object { '<li>' + (I $_) + '</li>' }) -join '') + "</$script:listTag>"); $items.Clear() }
    if ($quote.Count) { $out.Add('<blockquote><p>' + (($quote | ForEach-Object { I $_ }) -join ' ') + '</p></blockquote>'); $quote.Clear() }
  }

  $lines = ([string]$md -replace "`r", '') -split "`n"
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $raw = $lines[$i]
    $line = $raw.TrimEnd()
    if ($line -match '^\s*$') {
      # A blank line between two items of the same list keeps the list together
      $next = $null
      for ($j = $i + 1; $j -lt $lines.Count; $j++) { if ($lines[$j].Trim()) { $next = $lines[$j]; break } }
      $sameList = $items.Count -and $next -and (
        ($script:listTag -eq 'ul' -and $next -match '^\s*[-*+]\s+') -or ($script:listTag -eq 'ol' -and $next -match '^\s*\d+[.)]\s+'))
      if (-not $sameList) { & $flush }
      continue
    }
    if ($line -match '^(#{1,4})\s+(.*)$') {
      & $flush; $n = [math]::Max(2, $Matches[1].Length)
      $out.Add("<h$n>" + (I $Matches[2]) + "</h$n>"); continue
    }
    # A line ending in a backslash or two spaces is a line break inside the paragraph
    if ($raw -match '(\\|  )$' -and $line -notmatch '^\s*([-*+]|\d+[.)])\s+') {
      if ($items.Count -or $quote.Count) { & $flush }
      $para.Add($line.TrimEnd('\').Trim() + '<<BR>>'); continue
    }
    if ($line -match '^\s*[-*+]\s+(.*)$') {
      if ($para.Count -or $quote.Count -or ($items.Count -and $script:listTag -ne 'ul')) { & $flush }
      $script:listTag = 'ul'; $items.Add($Matches[1]); continue
    }
    if ($line -match '^\s*\d+[.)]\s+(.*)$') {
      if ($para.Count -or $quote.Count -or ($items.Count -and $script:listTag -ne 'ol')) { & $flush }
      $script:listTag = 'ol'; $items.Add($Matches[1]); continue
    }
    if ($line -match '^>\s?(.*)$') {
      if ($para.Count -or $items.Count) { & $flush }
      $quote.Add($Matches[1]); continue
    }
    if ($items.Count -or $quote.Count) { & $flush }
    $para.Add($line.Trim())
  }
  & $flush
  (($out -join "`n") -replace '&lt;&lt;BR&gt;&gt; ?', '<br>') -replace '<p>(<img [^>]+>)</p>', '<figure>$1</figure>'
}

# A photo, or a soft placeholder while no photo has been chosen
function Photo($src, $alt, $class, [switch]$Priority) {
  if ($src) {
    $p = if ($Priority) { ' fetchpriority="high"' } else { ' loading="lazy"' }
    "<div class=`"media $class`"><img src=`"$(E $src)`" alt=`"$(E $alt)`"$p></div>"
  } else {
    "<div class=`"media $class`"><div class=`"img-slot`">$(E $alt)</div></div>"
  }
}

function Format-Date($date, $lang) {
  $names = [Globalization.CultureInfo]::GetCultureInfo($cultures[$lang]).DateTimeFormat.MonthGenitiveNames
  "$($date.Day) $($names[$date.Month - 1]) $($date.Year)"
}

function Phone($S, $lang) { if ($lang -eq 'el') { $S.phone_display } else { $S.phone_display_intl } }

function Cta($title, $text, $U, $P) {
@"
    <section class="section section--tint">
      <div class="wrap prose reveal">
        <h2>$(I $title)</h2>
        <p>$(I $text)</p>
        <a class="btn btn--primary" href="$($P.booking)">$(E $U.book)</a>
      </div>
    </section>
"@
}

function MapBox($U, $S) {
  $q = [uri]::EscapeDataString($S.maps_query)
@"
        <div class="map" data-src="https://www.google.com/maps?q=$q&amp;output=embed" data-title="$(E $U.address)">
          <div class="map-consent">
            <p>$(E $U.map_note)</p>
            <div class="btn-row" style="justify-content: center;">
              <button class="btn btn--ghost" type="button" data-map-load>$(E $U.map_show)</button>
              <a class="btn btn--ghost" href="https://www.google.com/maps/search/?api=1&amp;query=$q" target="_blank" rel="noopener">$(E $U.map_directions)</a>
            </div>
          </div>
        </div>
"@
}

function Split($title, $bodyHtml, [switch]$Highlight) {
  $cls = if ($Highlight) { 'note' } else { 'prose' }
@"
        <div class="split reveal">
          <h2>$(I $title)</h2>
          <div class="$cls">
$bodyHtml
          </div>
        </div>
"@
}

# ---------------------------------------------------------------- articles

function Read-Article($file, $lang) {
  $raw = [IO.File]::ReadAllText($file.FullName, $utf8) -replace "`r", ''
  $m = [regex]::Match($raw, '^\s*(---|;;;|\+\+\+)\s*\n(.*?)\n\1\s*(\n|$)', 'Singleline')
  if (-not $m.Success) { throw "Missing front matter (--- ... ---) in $($file.FullName)" }
  $front = $m.Groups[2].Value.Trim()
  $meta = @{}
  if ($front.StartsWith('{')) {
    ($front | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $meta[$_.Name] = $_.Value }
  } else {
    foreach ($line in $front -split "`n") {
      $kv = [regex]::Match($line, '^\s*([a-z_]+):\s*(.*?)\s*$')
      if ($kv.Success) { $meta[$kv.Groups[1].Value] = $kv.Groups[2].Value.Trim('"', "'") }
    }
  }
  foreach ($k in 'title', 'date', 'description') {
    if (-not $meta[$k]) { throw "Article $($file.Name) is missing '$k'" }
  }
  $body = $raw.Substring($m.Length)
  $words = ([regex]::Matches($body, '\w+')).Count
  # PowerShell 7 (used on GitHub) turns ISO date strings in JSON into DateTime values
  $dateText = if ($meta.date -is [datetime]) { $meta.date.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture) }
              else { ([string]$meta.date).Substring(0, 10) }
  [pscustomobject]@{
    Slug = $file.BaseName
    Title = [string]$meta.title
    Description = [string]$meta.description
    Date = [datetime]::ParseExact($dateText, 'yyyy-MM-dd', $null)
    DateText = $dateText
    Image = [string]$meta.image
    ImageAlt = [string]$meta.image_alt
    Alt = [string]$meta.alt
    Draft = "$($meta.draft)" -eq 'true'
    Html = M $body
    Minutes = [math]::Max(1, [math]::Round($words / 200))
    Path = $paths[$lang].blog + $file.BaseName + '/'
  }
}

function ReadTime($a, $U) {
  $label = if ($a.Minutes -eq 1) { $U.blog_minute } else { $U.blog_minutes }
  "$($a.Minutes) $(E $label)"
}

function ArticleCards($articles, $lang, $U) {
  ($articles | ForEach-Object {
@"
          <article class="post-card">
            <p class="post-meta"><time datetime="$($_.DateText)">$(Format-Date $_.Date $lang)</time> | $(ReadTime $_ $U)</p>
            <h3><a href="$($_.Path)">$(E $_.Title)</a></h3>
            <p>$(E $_.Description)</p>
            <a class="link-arrow" href="$($_.Path)" aria-hidden="true" tabindex="-1">$(E $U.blog_read)</a>
          </article>
"@
  }) -join "`n"
}

# ---------------------------------------------------------------- pages

function Page-Home($lang, $C, $U, $S, $P, $services, $faq, $articles) {
  $creds = ($C.credentials | ForEach-Object { "            <li>$(I $_)</li>" }) -join "`n"
  $cards = ($services.items | ForEach-Object {
@"
          <a class="service-item" href="$($P.services)#$($_.id)">
            <h3>$(E $_.title)</h3>
            <p>$(I $_.summary)</p>
            <span class="link-arrow">$(E $U.more)</span>
          </a>
"@
  }) -join "`n"
  $words = ($C.approach_words | ForEach-Object { "          <span>$(E $_)</span>" }) -join "`n"
  $qa = ($faq.groups | ForEach-Object { $_.items } | Where-Object { $_.home } | ForEach-Object {
@"
          <details class="qa">
            <summary>$(E $_.q)</summary>
            <div class="answer">$(M $_.a)</div>
          </details>
"@
  }) -join "`n"
  $latest = ''
  if ($articles.Count) {
    $latest = @"
    <section class="section">
      <div class="wrap reveal">
        <h2>$(E $U.blog_latest)</h2>
        <div class="post-list post-list--home">
$(ArticleCards ($articles | Select-Object -First 3) $lang $U)
        </div>
        <p style="margin-top: 32px;"><a class="link-arrow" href="$($P.blog)">$(E $U.blog_back)</a></p>
      </div>
    </section>
"@
  }
@"
    <section class="hero">
      <div class="wrap">
        <div>
          <h1>$(E $U.name)</h1>
          <p class="role">$(E $U.role)</p>
          <p class="lead">$(I $C.hero_text)</p>
          <div class="btn-row">
            <a class="btn btn--primary" href="$($P.booking)">$(E $U.book)</a>
          </div>
        </div>
        $(Photo $S.portrait $U.portrait_alt 'media--portrait' -Priority)
      </div>
    </section>

    <section class="section" style="padding-top: 0;">
      <div class="wrap about reveal">
        $(Photo $S.office_photo $U.office_alt 'media--portrait')
        <div class="prose">
          <h2>$(I $C.welcome_title)</h2>
$(M $C.welcome_text)
          <ul class="creds">
$creds
          </ul>
          <a class="link-arrow" href="$($P.cv)">$(E $C.cv_link)</a>
        </div>
      </div>
    </section>

    <section class="section section--tint">
      <div class="wrap reveal">
        <div class="services-head">
          <h2>$(I $C.services_title)</h2>
          <p class="muted">$(I $C.services_text)</p>
        </div>
        <div class="service-list">
$cards
        </div>
      </div>
    </section>

    <section class="section">
      <div class="wrap cbt reveal">
        <p class="cbt-words" aria-hidden="true">
$words
        </p>
        <div class="prose">
          <h2>$(I $C.approach_title)</h2>
          <p>$(I $C.approach_text)</p>
          <a class="link-arrow" href="$($P.approach)">$(E $C.approach_link)</a>
        </div>
      </div>
    </section>

$latest
    <section class="section">
      <div class="wrap reveal">
        <h2>$(I $C.faq_title)</h2>
        <div class="prose" style="max-width: 820px; margin-top: 32px;">
$qa
          <p style="margin-top: 28px;"><a class="link-arrow" href="$($P.faq)">$(E $C.faq_link)</a></p>
        </div>
      </div>
    </section>

    <section class="section section--tint">
      <div class="wrap contact reveal">
        <div>
          <h2>$(I $C.contact_title)</h2>
          <dl>
            <div><dt>$(E $U.label_address)</dt><dd>$(E $U.address)</dd></div>
            <div><dt>$(E $U.label_phone)</dt><dd><a href="tel:$($S.phone_link)">$(E (Phone $S $lang))</a></dd></div>
            <div><dt>$(E $U.label_email)</dt><dd><a href="mailto:$(E $S.email)">$(E $S.email)</a></dd></div>
            <div><dt>$(E $U.label_sessions)</dt><dd>$(I $C.contact_sessions)</dd></div>
          </dl>
          <a class="btn btn--primary" href="$($P.booking)">$(E $U.book)</a>
        </div>
$(MapBox $U $S)
      </div>
    </section>
"@
}

function Page-Cv($lang, $C, $U, $S, $P) {
  $sections = ($C.sections | ForEach-Object { Split $_.title (M $_.body) }) -join "`n"
@"
    <section class="page-head">
      <div class="wrap about">
        $(Photo $S.portrait $U.portrait_alt 'media--portrait')
        <div class="prose">
          <h1>$(I $C.title)</h1>
          <p class="lead">$(I $C.lead)</p>
$(M $C.intro)
        </div>
      </div>
    </section>

    <section class="section section--tight">
      <div class="wrap">
$sections
      </div>
    </section>

$(Cta $C.cta_title $C.cta_text $U $P)
"@
}

function Page-Approach($lang, $C, $U, $S, $P) {
  $sections = ($C.sections | ForEach-Object { Split $_.title (M $_.body) -Highlight:([bool]$_.highlight) }) -join "`n"
@"
    <section class="page-head">
      <div class="wrap prose">
        <h1>$(I $C.title)</h1>
        <p class="lead">$(I $C.lead)</p>
      </div>
    </section>

    <section class="section section--tight">
      <div class="wrap">
$sections
      </div>
    </section>

$(Cta $C.cta_title $C.cta_text $U $P)
"@
}

function Page-Services($lang, $C, $U, $S, $P) {
  $jump = ($C.items | ForEach-Object { "          <a href=`"#$($_.id)`">$(E $_.short_title)</a>" }) -join "`n"
  $blocks = ($C.items | ForEach-Object {
    $noteCls = if ($_.highlight) { 'note' } else { 'muted prose' }
@"
      <section class="service reveal" id="$($_.id)">
        <h2>$(E $_.title)</h2>
        <p class="lead">$(I $_.lead)</p>
        <div class="service-cols">
          <div class="panel">
            <h3>$(E $_.for_you_title)</h3>
$(M $_.for_you)
          </div>
          <div class="panel">
            <h3>$(E $_.how_title)</h3>
$(M $_.how)
          </div>
        </div>
        <div class="$noteCls">$(M $_.note)</div>
      </section>
"@
  }) -join "`n"
@"
    <section class="page-head">
      <div class="wrap prose">
        <h1>$(I $C.title)</h1>
        <p class="lead">$(I $C.lead)</p>
        <nav class="jump" aria-label="$(E $C.title)">
$jump
        </nav>
      </div>
    </section>

    <div class="wrap">
$blocks
    </div>

$(Cta $C.cta_title $C.cta_text $U $P)
"@
}

function Page-Faq($lang, $C, $U, $S, $P) {
  $groups = ($C.groups | ForEach-Object {
    $items = ($_.items | ForEach-Object {
@"
          <details class="qa">
            <summary>$(E $_.q)</summary>
            <div class="answer">$(M $_.a)</div>
          </details>
"@
    }) -join "`n"
@"
        <div class="faq-group reveal">
          <h2>$(E $_.title)</h2>
$items
        </div>
"@
  }) -join "`n"
@"
    <section class="page-head">
      <div class="wrap prose">
        <h1>$(I $C.title)</h1>
        <p class="lead">$(I $C.lead)</p>
      </div>
    </section>

    <section class="section section--tight">
      <div class="wrap" style="max-width: 900px;">
$groups
        <div class="note reveal">$(M $C.closing)</div>
      </div>
    </section>
"@
}

function Page-Booking($lang, $C, $U, $S, $P) {
  $phone = Phone $S $lang
@"
    <section class="page-head">
      <div class="wrap prose">
        <h1>$(I $C.title)</h1>
        <p class="lead">$(I $C.lead)</p>
      </div>
    </section>

    <section class="section section--tight">
      <div class="wrap contact">
        <div>
          <dl>
            <div><dt>$(E $U.label_phone)</dt><dd><a href="tel:$($S.phone_link)">$(E $phone)</a></dd></div>
            <div><dt>$(E $U.label_email)</dt><dd><a href="mailto:$(E $S.email)">$(E $S.email)</a></dd></div>
            <div><dt>$(E $U.label_address)</dt><dd>$(E $U.address)</dd></div>
            <div><dt>$(E $U.label_hours)</dt><dd>$(I $C.hours)</dd></div>
          </dl>
$(MapBox $U $S)
        </div>

        <div>
          <h2>$(I $C.form_title)</h2>
          <form class="form" data-web3forms
                data-sending="$(E $U.form_sending)" data-success="$(E $U.form_success)" data-failure="$(E $U.form_failure)">
            <input type="hidden" name="access_key" value="$(E $S.web3forms_key)">
            <input type="hidden" name="subject" value="$(E $U.name) - $(E $C.form_title)">
            <input type="hidden" name="from_name" value="$siteUrl">
            <input type="checkbox" name="botcheck" class="hp" tabindex="-1" autocomplete="off" aria-hidden="true">
            <p class="form-note">$(I $C.form_note)</p>
            <div class="field">
              <label for="f-name">$(E $U.form_name)</label>
              <input id="f-name" name="name" type="text" autocomplete="name" required maxlength="100">
            </div>
            <div class="field">
              <label for="f-email">$(E $U.form_email)</label>
              <input id="f-email" name="email" type="email" autocomplete="email" required maxlength="120">
            </div>
            <div class="field">
              <label for="f-phone">$(E $U.form_phone)</label>
              <input id="f-phone" name="phone" type="tel" autocomplete="tel" maxlength="30">
            </div>
            <div class="field">
              <label for="f-msg">$(E $U.form_message)</label>
              <textarea id="f-msg" name="message" required maxlength="1000"></textarea>
            </div>
            <label class="check">
              <input type="checkbox" name="consent" value="yes" required>
              <span>$(I $U.form_consent)</span>
            </label>
            <div class="btn-row" style="align-items: center;">
              <button class="btn btn--primary" type="submit">$(E $U.form_send)</button>
              <p class="form-status" role="status" aria-live="polite" style="margin: 0;"></p>
            </div>
          </form>
          <div class="prose" hidden>
            <p>$(I $C.fallback)</p>
            <p><a href="tel:$($S.phone_link)">$(E $phone)</a><br><a href="mailto:$(E $S.email)">$(E $S.email)</a></p>
          </div>
        </div>
      </div>
    </section>
"@
}

function Page-Privacy($lang, $C, $U, $S, $P) {
  $sections = ($C.sections | ForEach-Object { Split $_.title (M $_.body) }) -join "`n"
@"
    <section class="page-head">
      <div class="wrap prose">
        <h1>$(I $C.title)</h1>
        <p class="lead">$(I $C.lead)</p>
$(M $C.intro)
      </div>
    </section>

    <section class="section section--tight">
      <div class="wrap">
$sections
      </div>
    </section>
"@
}

function Page-BlogIndex($lang, $U, $articles) {
  $list = if ($articles.Count) { "        <div class=`"post-list`">`n" + (ArticleCards $articles $lang $U) + "`n        </div>" }
          else { "        <p class=`"note`">$(E $U.blog_empty)</p>" }
@"
    <section class="page-head">
      <div class="wrap prose">
        <h1>$(E $U.blog_title)</h1>
        <p class="lead">$(I $U.blog_lead)</p>
      </div>
    </section>
    <section class="section section--tight">
      <div class="wrap">
$list
      </div>
    </section>
"@
}

function Page-Article($lang, $a, $U, $P) {
  $image = if ($a.Image) { "<figure class=`"post-cover`"><img src=`"$(E $a.Image)`" alt=`"$(E $a.ImageAlt)`" fetchpriority=`"high`"></figure>" } else { '' }
  $ld = '{"@context":"https://schema.org","@type":"BlogPosting","headline":' + (ConvertTo-Json $a.Title) +
    ',"datePublished":"' + $a.DateText + '","author":{"@type":"Person","name":' + (ConvertTo-Json ([string]$U.name)) + '},"inLanguage":"' + $lang + '"}'
@"
    <article class="post">
      <header class="page-head">
        <div class="wrap prose">
          <p class="post-meta"><a href="$($P.blog)">$(E $U.blog_back)</a> | <time datetime="$($a.DateText)">$(Format-Date $a.Date $lang)</time> | $(ReadTime $a $U)</p>
          <h1>$(E $a.Title)</h1>
          <p class="lead">$(E $a.Description)</p>
        </div>
      </header>
      <div class="wrap">
        $image
        <div class="post-body prose">
$($a.Html)
        </div>
        <p class="post-disclaimer prose">$(E $U.blog_disclaimer)</p>
      </div>
    </article>
    <script type="application/ld+json">$ld</script>

$(Cta $U.blog_cta_title $U.blog_cta_text $U $P)
"@
}

function Page-NotFound($U, $P, $O) {
@"
    <section class="section">
      <div class="wrap prose">
        <h1>$(E $U.notfound_title)</h1>
        <p class="lead">$(E $U.notfound_text)</p>
        <div class="btn-row">
          <a class="btn btn--primary" href="$($P.home)">$(E $U.notfound_home)</a>
          <a class="btn btn--ghost" href="$($O.home)">$(E $U.lang_name)</a>
        </div>
      </div>
    </section>
"@
}

# ---------------------------------------------------------------- layout

function Layout($lang, $U, $S, $P, $meta, $body) {
  $otherLang = if ($lang -eq 'el') { 'en' } else { 'el' }
  $locale = if ($lang -eq 'el') { 'el_GR' } else { 'en_GB' }
  $nav = foreach ($k in 'home', 'cv', 'approach', 'services', 'blog', 'faq') {
    $cur = if ($meta.nav -eq $k) { ' aria-current="page"' } else { '' }
    "        <a href=`"$($P[$k])`"$cur>$(E $U."nav_$k")</a>"
  }
  $bookCur = if ($meta.nav -eq 'booking') { ' aria-current="page"' } else { '' }
  # Until the site is switched to public, search engines are asked not to list it
  $robots = if ($S.public -eq $true) { '' } else { "`n  <meta name=`"robots`" content=`"noindex, nofollow`">" }
  # Preview image for links shared on Viber, Facebook etc.: an article's cover, otherwise the logo card
  $image = if ($meta.image) { $meta.image } else { '/assets/img/social.png' }
  $imageAlt = if ($meta.image) { $meta.imageAlt } else { "$($U.name), $($U.role)" }
  $footerPages = foreach ($k in 'cv', 'approach', 'services', 'blog', 'faq') { "            <li><a href=`"$($P[$k])`">$(E $U."nav_$k")</a></li>" }
  $ld = '{"@context":"https://schema.org","@type":"Psychologist","name":' + (ConvertTo-Json ([string]$U.name)) +
    ',"url":"' + $siteUrl + $P.home + '","telephone":"' + $S.phone_link + '","email":"' + $S.email +
    '","address":{"@type":"PostalAddress","streetAddress":' + (ConvertTo-Json ([string]$U.address)) + ',"addressCountry":"GR"}}'
@"
<!doctype html>
<html lang="$lang">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$(E $meta.title)</title>
  <meta name="description" content="$(E $meta.description)">$robots
  <link rel="canonical" href="$siteUrl$($meta.path)">
  <link rel="alternate" hreflang="$lang" href="$siteUrl$($meta.path)">
  <link rel="alternate" hreflang="$otherLang" href="$siteUrl$($meta.alt)">
  <meta property="og:type" content="website">
  <meta property="og:locale" content="$locale">
  <meta property="og:title" content="$(E $meta.title)">
  <meta property="og:description" content="$(E $meta.description)">
  <meta property="og:url" content="$siteUrl$($meta.path)">
  <meta property="og:site_name" content="$(E $U.name)">
  <meta property="og:image" content="$siteUrl$(E $image)">
  <meta property="og:image:alt" content="$(E $imageAlt)">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="theme-color" content="#f3f5f2" media="(prefers-color-scheme: light)">
  <meta name="theme-color" content="#131a19" media="(prefers-color-scheme: dark)">
  <link rel="icon" href="/assets/img/icon-32.png" sizes="32x32" type="image/png">
  <link rel="icon" href="/assets/img/icon-512.png" sizes="512x512" type="image/png">
  <link rel="apple-touch-icon" href="/assets/img/icon-180.png">
  <link rel="preconnect" href="https://fonts.bunny.net">
  <link rel="stylesheet" href="https://fonts.bunny.net/css?family=commissioner:400,500,600|literata:400,400i,500&amp;display=swap">
  <link rel="stylesheet" href="/assets/site.css">
  <script type="application/ld+json">$ld</script>
  <script src="/assets/site.js" defer></script>
</head>
<body>
  <a class="skip" href="#main">$(E $U.skip)</a>

  <header class="site-header">
    <div class="wrap">
      <a class="brand" href="$($P.home)">
        <img class="brand-logo" src="/assets/img/logo.png" alt="" width="313" height="304">
        <span class="brand-text">
        <strong>$(E $U.name)</strong>
        <span>$(E $U.role)</span></span>
      </a>
      <nav id="nav" class="nav">
$($nav -join "`n")
        <a class="btn btn--primary nav-book" href="$($P.booking)"$bookCur>$(E $U.book)</a>
      </nav>
      <a class="lang" href="$($meta.alt)" hreflang="$otherLang" lang="$otherLang" aria-label="$(E $U.lang_name)">$(E $U.lang_short)</a>
      <a class="btn btn--primary header-cta" href="$($P.booking)">$(E $U.book)</a>
      <button class="menu-toggle" type="button" aria-controls="nav" aria-expanded="false" data-open="$(E $U.menu)" data-close="$(E $U.close)">$(E $U.menu)</button>
    </div>
  </header>

  <main id="main">
$body
  </main>

  <footer class="site-footer">
    <div class="wrap">
      <p class="emergency">$(I $U.emergency)</p>
      <div class="footer-grid">
        <div>
          <img class="footer-logo" src="/assets/img/logo.png" alt="" width="313" height="304" loading="lazy">
          <h2>$(E $U.name)</h2>
          <p class="muted">$(E $U.role)<br>$(E $U.footer_text)</p>
        </div>
        <div>
          <h2>$(E $U.footer_pages)</h2>
          <ul>
$($footerPages -join "`n")
          </ul>
        </div>
        <div>
          <h2>$(E $U.footer_contact)</h2>
          <ul>
            <li>$(E $U.address)</li>
            <li><a href="tel:$($S.phone_link)">$(E (Phone $S $lang))</a></li>
            <li><a href="mailto:$(E $S.email)">$(E $S.email)</a></li>
          </ul>
        </div>
      </div>
      <div class="legal">
        <span>&copy; $(E $U.name). $(E $U.rights)</span>
        <a href="$($P.privacy)">$(E $U.privacy)</a>
      </div>
    </div>
  </footer>
</body>
</html>
"@
}

# ---------------------------------------------------------------- build

if (Test-Path $dist) { Remove-Item $dist -Recurse -Force }
New-Item -ItemType Directory -Path $dist | Out-Null
Copy-Item (Join-Path $root 'assets') (Join-Path $dist 'assets') -Recurse
if (Test-Path (Join-Path $root 'public')) { Get-ChildItem (Join-Path $root 'public') -File | ForEach-Object { Copy-Item $_.FullName $dist } }

$S = Read-Json 'content/settings.json'
$sitemap = New-Object System.Collections.Generic.List[string]

function Write-Page($lang, $U, $P, $meta, $body) {
  $html = Layout $lang $U $S $P $meta $body
  if ($meta.path -eq '/404') {
    $out = Join-Path $dist '404.html'
  } else {
    $dir = Join-Path $dist ($meta.path.Trim('/'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $out = Join-Path $dir 'index.html'
    $sitemap.Add("  <url><loc>$siteUrl$($meta.path)</loc></url>")
  }
  [IO.File]::WriteAllText($out, $html, $utf8)
  Write-Host "built $($meta.path)"
}

foreach ($lang in 'el', 'en') {
  $P = $paths[$lang]
  $O = if ($lang -eq 'el') { $paths.en } else { $paths.el }
  $U = Read-Json "content/$lang/ui.json"
  $C = @{}
  foreach ($name in 'home', 'cv', 'approach', 'services', 'faq', 'booking', 'privacy') { $C[$name] = Read-Json "content/$lang/$name.json" }

  $articles = @()
  $blogDir = Join-Path $root "content/blog/$lang"
  if (Test-Path $blogDir) {
    $articles = @(Get-ChildItem $blogDir -Filter *.md | ForEach-Object { Read-Article $_ $lang } |
      Where-Object { -not $_.Draft } | Sort-Object Date -Descending)
  }

  $pages = [ordered]@{
    home = Page-Home $lang $C.home $U $S $P $C.services $C.faq $articles
    cv = Page-Cv $lang $C.cv $U $S $P
    approach = Page-Approach $lang $C.approach $U $S $P
    services = Page-Services $lang $C.services $U $S $P
    faq = Page-Faq $lang $C.faq $U $S $P
    booking = Page-Booking $lang $C.booking $U $S $P
    privacy = Page-Privacy $lang $C.privacy $U $S $P
  }
  foreach ($k in $pages.Keys) {
    Write-Page $lang $U $P @{ title = $C[$k].meta_title; description = $C[$k].meta_description; path = $P[$k]; alt = $O[$k]; nav = $k } $pages[$k]
  }

  Write-Page $lang $U $P @{ title = $U.blog_meta_title; description = $U.blog_meta_description; path = $P.blog; alt = $O.blog; nav = 'blog' } (Page-BlogIndex $lang $U $articles)
  foreach ($a in $articles) {
    $alt = if ($a.Alt) { $a.Alt } else { $O.blog }
    Write-Page $lang $U $P @{ title = "$($a.Title) | $($U.name)"; description = $a.Description; path = $a.Path; alt = $alt; nav = 'blog'; image = $a.Image; imageAlt = $a.ImageAlt } (Page-Article $lang $a $U $P)
  }

  if ($lang -eq 'el') {
    Write-Page $lang $U $P @{ title = $U.notfound_title; description = $U.notfound_text; path = '/404'; alt = $O.home; nav = '' } (Page-NotFound $U $P $O)
  }
}

# Every internal link, anchor and image must point at something that exists.
# On GitHub a failure stops the publish, so a typo never reaches the live site.
$broken = New-Object System.Collections.Generic.List[string]
$pagesHtml = @{}
Get-ChildItem $dist -Recurse -Filter *.html | ForEach-Object { $pagesHtml[$_.FullName] = [IO.File]::ReadAllText($_.FullName, $utf8) }
foreach ($file in $pagesHtml.Keys) {
  $from = '/' + $file.Substring($dist.Length + 1).Replace('\', '/') -replace 'index\.html$', ''
  foreach ($m in [regex]::Matches($pagesHtml[$file], '(?:href|src)="(/(?!/)[^"#?]*)(#[^"]*)?"')) {
    $target = Join-Path $dist ([uri]::UnescapeDataString($m.Groups[1].Value.TrimStart('/')))
    $page = if (Test-Path $target -PathType Leaf) { $target } elseif (Test-Path (Join-Path $target 'index.html')) { Join-Path $target 'index.html' } else { $null }
    if (-not $page) { $broken.Add("$from -> $($m.Groups[1].Value)"); continue }
    $anchor = $m.Groups[2].Value.TrimStart('#')
    if ($anchor -and $pagesHtml[$page] -notmatch ('id="' + [regex]::Escape($anchor) + '"')) { $broken.Add("$from -> $($m.Groups[1].Value)#$anchor") }
  }
}
if ($broken.Count) {
  $broken | Sort-Object -Unique | ForEach-Object { Write-Host "BROKEN LINK: $_" }
  throw "$($broken.Count) broken link(s), see the lines above"
}
Write-Host 'links ok'

$xml = "<?xml version=`"1.0`" encoding=`"UTF-8`"?>`n<urlset xmlns=`"http://www.sitemaps.org/schemas/sitemap/0.9`">`n" + ($sitemap -join "`n") + "`n</urlset>`n"
[IO.File]::WriteAllText((Join-Path $dist 'sitemap.xml'), $xml, $utf8)
$robotsTxt = if ($S.public -eq $true) { "User-agent: *`nAllow: /`n`nSitemap: $siteUrl/sitemap.xml`n" } else { "User-agent: *`nDisallow: /`n" }
[IO.File]::WriteAllText((Join-Path $dist 'robots.txt'), $robotsTxt, $utf8)
Write-Host "public: $($S.public -eq $true)"
Write-Host "done -> $dist"
