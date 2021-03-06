library dartdocorg.generators.index_generator;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartdocorg/config.dart';
import 'package:dartdocorg/package.dart';
import 'package:dartdocorg/utils.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart';
import 'package:resource/resource.dart' as r;

var _logger = new Logger("index_generator");

class IndexGenerator {
  final Config config;
  IndexGenerator(this.config);

  Future<Null> generateErrors(Iterable<Package> packages) async {
    Map<String, Iterable<Package>> groupedPackages =
        groupBy(packages, (package) => package.name);
    var html = new StringBuffer();
    html.writeln(_generateHeader(MenuItem.failed));
    html.writeln("<dl>");
    groupedPackages.forEach((name, packageVersions) {
      List<Package> sortedPackageVersions = new List.from(packageVersions)
        ..sort((a, b) => b.compareTo(a));
      html.writeln(
          '<dt>${sortedPackageVersions.first.name}</dt><dd class="text-muted">');
      html.write(sortedPackageVersions.map((package) {
        return "<a href='/${config.gcsPrefix}/${package.name}/${package.version}/log.txt'>${package.version}</a>";
      }).join(' &bull;\n'));
      html.writeln("</dd>");
    });
    html.writeln("</dl>");
    html.writeln(_generateFooter());
    await writeToFile(MenuItem.failed.url, html.toString());
  }

  Future<Null> generateHistory(
      List<Package> sortedPackages, Set<Package> successfulPackages) async {
    var html = new StringBuffer();
    html.writeln(_generateHeader(MenuItem.history));
    html.writeln("<table class='table table-hover'>");
    html.writeln(
        "<thead><tr><th>Package</th><th>Time</th><th>Status</th><th>Log</th></thead>");
    html.writeln("<tbody>");
    sortedPackages.forEach((package) {
      var isSuccessful = successfulPackages.contains(package);
      html.writeln("<tr${isSuccessful ? '' : ' class="danger"'}>");
      if (isSuccessful) {
        html.writeln(
            "<td><a href='/${package.url(config)}/index.html'>${package.fullName}</a></td>");
      } else {
        html.writeln("<td>${package.fullName}</td>");
      }
      html.writeln("<td>${package.updatedAt}</td>");
      html.writeln("<td>${isSuccessful ? 'Success' : '<em>Failure</em>'}</td>");
      html.writeln(
          "<td><a href='/${package.logUrl(config)}'>build log</a></td>");
      html.writeln("</tr>");
    });
    html.writeln("</tbody></table>");
    html.writeln(_generateFooter());
    await writeToFile(MenuItem.history.url, html.toString());
  }

  Future<Null> generateHome(Iterable<Package> packages) async {
    Map<String, Iterable<Package>> groupedPackages =
        groupBy(packages, (package) => package.name);
    var html = new StringBuffer();
    html.writeln(_generateHeader(MenuItem.home));
    html.writeln("<dl>");
    groupedPackages.forEach((name, packageVersions) {
      List<Package> sortedPackageVersions = new List.from(packageVersions)
        ..sort((a, b) => b.compareTo(a));
      html.writeln(
          '<dt>${sortedPackageVersions.first.name}</dt><dd class="text-muted">');
      html.write(sortedPackageVersions.map((package) {
        return "<a href='/${config.gcsPrefix}/${package.name}/${package.version}/index.html'>${package.version}</a>";
      }).join(' &bull;\n'));
      html.writeln("</dd>");
    });
    html.writeln("</dl>");
    html.writeln(_generateFooter());
    await writeToFile(MenuItem.home.url, html.toString());
  }

  Future<Null> copyAssets() async {
    var favicon = config.mode == ConfigMode.CROSSDART ? "favicon-crossdart.png" : "favicon-dart.png";
    for (var data in [[favicon, "favicon.png"], "style.css"]) {
      String source;
      String target;
      if (data is Iterable) {
        source = data[0];
        target = data[1];
      } else {
        source = data;
        target = data;
      }
      var resource = new r.Resource("package:dartdocorg/resources/${source}");
      new Directory(path.join(config.outputDir, "assets")).createSync(recursive: true);
      new File(path.join(config.outputDir, "assets", target)).writeAsBytesSync(await resource.readAsBytes());
    }
  }

  Future<Null> generateJsonIndex(Iterable<Package> packages) async {
    var finalMap = packages.fold({}, (Map memo, Package package) {
      if (memo[package.name] == null) {
        memo[package.name] = {"versions": {}};
      }
      var url = "${config.hostedUrl}/${package.url(config)}";
      memo[package.name]["versions"][package.version.toString()] = {
        "html": "$url/index.html",
        "archive": "$url/package.tar.gz"
      };
      return memo;
    });
    finalMap.forEach((name, values) {
      var versions = values["versions"].keys.map((v) => new Version.parse(v)).toList();
      versions.sort();
      values["versions_order"] = versions.map((v) => v.toString()).toList();
    });
    await writeToFile("index.json", JSON.encode(finalMap));
  }

  Future<Null> generate404() async {
    var html = new StringBuffer();
    html.writeln(_generateHeader());
    html.writeln("""
      <div class="row">
        <div class="col-md-12">
          <div class="jumbotron center">
              <h1>Page Not Found <small><font face="Tahoma" color="red">Error 404</font></small></h1>
              <br />
              <p>The page you requested could not be found. Its possible documentation was not built for the package
                requested. Check the <a href="/${MenuItem.failed.url}">build failures</a> page for your package.</p>
              <a href="/${MenuItem.home.url}" class="btn btn-lg btn-info"><i class="glyphicon glyphicon-home glyphicon-white"></i> dartdocs home</a>
            </div>
            <br />
        </div>
      </div>""");
    html.writeln(_generateFooter());
    await writeToFile("404.html", html.toString());
  }

  Future<Null> writeToFile(String filePath, String contents) async {
    var file = new File(path.join(config.outputDir, filePath));
    await file.create(recursive: true);
    await file.writeAsString(contents);
  }

  String _generateFooter() {
    var suffix = config.mode == ConfigMode.CROSSDART ? "crossdart" : "dartdocs";
    return "</div>" +
      new File(path.join(config.dirroot, "resources", "google_analytics_${suffix}.html")).readAsStringSync() +
      "</body></html>";
  }

  String get _bodyClass => config.mode == ConfigMode.CROSSDART ? "crossdart-body" : "dartdocs-body";
  String get _siteName => config.mode == ConfigMode.CROSSDART ? "Crossdart" : "Dart Docs";
  String get _gitRepo => config.mode == ConfigMode.CROSSDART ? "astashov/crossdart" : "astashov/dartdocs.org";
  String get _crossdartChromeExtension {
    if (config.mode == ConfigMode.CROSSDART) {
      return "<a href=\"https://github.com/astashov/crossdart-chrome-extension\">Crossdart Chrome Extension for Github</a> |";
    } else {
      return "";
    }
  }
  String get _title {
    if (config.mode == ConfigMode.CROSSDART) {
      return "CrossDart - cross-referenced Dart's pub packages";
    } else {
      return "Dartdocs - Documentation for Dart packages";
    }
  }

  String _generateHeader([MenuItem activeItem]) {
    return """<html>
  <head>
    <title>${_title}</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link rel="stylesheet" href="//netdna.bootstrapcdn.com/bootstrap/3.1.1/css/bootstrap.min.css">
    <link rel="stylesheet" href="/assets/style.css">
    <link rel='icon' href='/assets/favicon.png' />
  </head>
  <body class="${_bodyClass}">
    <nav class="navbar navbar-default" role="navigation">
      <div class="container-fluid">
        <div class="title">${_siteName}</div>
        <ul class="nav navbar-nav">
          ${MenuItem.all.map((mi) => mi.toHtml(mi == activeItem)).join("\n")}
        </ul>
        <p class="navbar-text pull-right">
          ${_crossdartChromeExtension}
          <a href="https://github.com/${_gitRepo}">Github</a> |
          <a href="https://github.com/${_gitRepo}/issues">Issues</a>
        </p>
      </div>
    </nav>
    <div class="container">""";
  }
}

class MenuItem {
  static const MenuItem home = const MenuItem("index.html", "Home");
  static const MenuItem history =
      const MenuItem("history/index.html", "Build history");
  static const MenuItem failed =
      const MenuItem("failed/index.html", "Build failures");
  static const Iterable<MenuItem> all = const [home, history, failed];

  final String url;
  final String title;
  const MenuItem(this.url, this.title);

  String toHtml(bool isActive) {
    return "<li${isActive ? " class='active'" : ""}><a href='/$url'>$title</a></li>";
  }
}

final Iterable<String> allIndexUrls = []
  ..addAll(MenuItem.all.map((mi) => mi.url))
  ..add("index.json")
  ..add("assets/style.css")
  ..add("assets/favicon.png");
