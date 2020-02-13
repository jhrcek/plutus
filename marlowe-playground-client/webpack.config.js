'use strict';

const MonacoWebpackPlugin = require('monaco-editor-webpack-plugin');
const HtmlWebpackPlugin = require('html-webpack-plugin');
const path = require('path');
const webpack = require('webpack');

const isWebpackDevServer = process.argv.some(a => path.basename(a) === 'webpack-dev-server');

const isWatch = process.argv.some(a => a === '--watch');

const plugins =
    isWebpackDevServer || !isWatch ? [] : [
        function () {
            this.plugin('done', function (stats) {
                process.stderr.write(stats.toString('errors-only'));
            });
        }
    ]
    ;

module.exports = {
    devtool: 'eval-source-map',

    devServer: {
        contentBase: path.join(__dirname, "dist"),
        compress: true,
        port: 8009,
        https: true,
        proxy: {
            "/api": {
                target: 'http://localhost:8080'
            }
        }
    },

    entry: './entry.js',

    output: {
        path: path.join(__dirname, 'dist'),
        pathinfo: true,
        filename: 'app.[hash].js'
    },

    module: {
        rules: [
            { test: /\.woff(2)?(\?v=[0-9]\.[0-9]\.[0-9])?$/, loader: "url-loader?limit=10000&mimetype=application/font-woff" },
            { test: /fontawesome-.*\.(ttf|eot|svg)(\?v=[0-9]\.[0-9]\.[0-9])?$/, loader: "file-loader" },
            {
                test: /\.ne$/,
                loader: 'nearley-webpack-loader',
                options: {
                    baseDir: '.'
                }
            },
            {
                test: /\.purs$/,
                use: [
                    {
                        loader: 'purs-loader',
                        options: {
                            src: [
                                'src/**/*.purs',
                                'generated/**/*.purs',
                                '.spago/*/*/src/**/*.purs',
                                '../playground-common/src/**/*.purs',
                                '../web-common/src/**/*.purs'
                            ],
                            psc: null,
                            bundle: !(isWebpackDevServer || isWatch),
                            warnings: true,
                            watch: isWebpackDevServer || isWatch,
                            pscPackage: false,
                            pscIde: false
                        }
                    }
                ]
            },
            {
                test: /\.css$/,
                use: ['style-loader', 'css-loader']
            },
            {
                test: /\.scss$/,
                use: ['style-loader', 'css-loader', 'sass-loader']
            },
            {
                test: /\.(gif|png|jpe?g|svg)$/i,
                use: 'url-loader'
            },
            {
                test: /\.ttf$/,
                use: ['file-loader'],
            }
        ]
    },

    resolve: {
        modules: [
            'node_modules'
        ],
        alias: {
            grammar: path.resolve(__dirname, './grammar.ne')
        },
        extensions: ['.purs', '.js']
    },

    resolveLoader: {
        modules: [
            'node_modules',
            path.resolve(__dirname, '.')
        ]
    },

    plugins: [
        new webpack.LoaderOptionsPlugin({
            debug: true
        }),
        new HtmlWebpackPlugin({
            template: '../web-common/static/index.html',
            favicon: 'static/favicon.ico',
            title: 'Marlowe Playground',
            productName: 'marlowe-playground',
            googleAnalyticsId: isWebpackDevServer ? 'UA-XXXXXXXXX-X' : 'UA-119953429-7'
        }),
        new webpack.NormalModuleReplacementPlugin(/^echarts$/, 'echarts/dist/echarts.min.js'),
        new MonacoWebpackPlugin()
    ].concat(plugins)
};
