# Grade Adjust

A Flutter app which allows calculation of the expected time at various points on a GPX route given a constant grade adjusted pace. 
The app also includes a grade adjusted pace calculator. The grade adjustment calculations are based on https://medium.com/strava-engineering/an-improved-gap-model-8b07ae8886c3

## Live Demo

You can try the app online at: [https://yourusername.github.io/grade-adjust/](https://yourusername.github.io/grade-adjust/)

## Features

- Upload GPX files to analyze routes
- View route on an interactive map
- See elevation profile with color-coded gradients
- Calculate estimated time based on grade-adjusted pace
- Hover over the map or elevation chart to see detailed information
- Responsive design that works on desktop and mobile

## Development

### Prerequisites

- Flutter SDK (3.19.0 or later)
- Dart SDK

### Setup

1. Clone the repository
2. Run `flutter pub get` to install dependencies
3. Run `flutter run -d chrome` to start the app in development mode

### Building for Web

```bash
flutter build web --release --base-href "/grade-adjust/"
```

## Deployment

The app is automatically deployed to GitHub Pages when changes are pushed to the master branch. The deployment is handled by GitHub Actions workflow.
