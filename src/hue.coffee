_                   = require 'lodash'
url                 = require 'url'
request             = require 'request'
tinycolor           = require 'tinycolor2'
debug               = require('debug')('hue-util:hue')

HUE_SAT_MODIFIER    = 254
HUE_DEGREE_MODIFIER = 182.04
BUTTON_EVENTS       = 16: '2', 17: '3', 18: '4', 34: '1'

class Hue
  constructor: (@app='hue-util', @ipAddress, @username, @onUsernameChange=->) ->

  getUri: (path) =>
    url.format
      protocol: 'http'
      hostname: @ipAddress
      pathname: path

  handleResponse: (callback=->) =>
    (error, response, body) =>
      debug 'got response', error, response.statusCode, body
      return callback error if error?
      return callback body if response.statusCode > 400
      if body?[0]?.error?
        debug 'got hue error', body[0].error
        return callback body[0].error
      callback null, body

  verify: (callback=->) =>
    debug 'verifying'
    @getBridgeIp (error, ipAddress) =>
      return callback error if error?
      @checkHueBridge (error) =>
        return @createUser callback if error?
        callback()

  getBridgeIps: (callback=->) =>
    requestOptions =
      method: 'GET'
      uri: 'https://www.meethue.com/api/nupnp'
      json: true
    debug 'getting bridge ips', requestOptions
    request requestOptions, @handleResponse (error, body) =>
      return callback error if error?
      callback null, _.pluck body, 'internalipaddress'

  getBridgeIp: (callback=->)=>
    debug 'getting bridge ip', defaultIpAddress: @ipAddress
    return callback null, @ipAddress if @ipAddress?
    @getBridgeIps (error, ips) =>
      return callback error if error?
      debug 'got ip addresses', ips
      @ipAddress = _.first ips
      debug 'using ipAddress', @ipAddress
      callback null, @ipAddress

  checkHueBridge: (callback=->) =>
    requestOptions =
      method: 'GET'
      uri: @getUri "/api/#{@app}"
      json: true
    debug 'check hue bridge', requestOptions
    request requestOptions, @handleResponse(callback)

  createUser: (callback=->) =>
    return callback null if @username
    requestOptions =
      method: 'POST'
      uri: @getUri "/api"
      json: devicetype: @app
    debug 'creating user', requestOptions
    request requestOptions, @handleResponse (error, body) =>
      if body?[0]?.success?.username
        @username = body[0].success.username
        @onUsernameChange @username
      callback error, body

  changeLights: (options={}, callback=->) =>
    @verify (error) =>
      return callback error if error?
      endpoint = 'lights'
      action = 'state'

      endpoint = 'groups' if options.useGroup
      action = 'action' if options.useGroup

      hsv = tinycolor(options.color).toHsv()
      body = _.pick options, ['on', 'alert', 'effect', 'transitiontime']

      colorDefaults =
        bri: parseInt(hsv.v * HUE_SAT_MODIFIER)
        hue: parseInt(hsv.h * HUE_DEGREE_MODIFIER)
        sat: parseInt(hsv.s * HUE_SAT_MODIFIER)
      body = _.extend colorDefaults, body if options.color

      requestOptions =
        method: 'PUT'
        uri: @getUri "/api/#{@username}/#{endpoint}/#{options.lightNumber}/#{action}"
        json: body
      debug 'changing lights', requestOptions
      request requestOptions, @handleResponse(callback)

  checkButtons: (sensorName, callback=->) =>
    debug 'checking buttons'
    @checkSensors (error, body) =>
      return callback error if error?
      state = _.findWhere(_.values(body), name: sensorName).state
      debug 'got state', state
      callback button: BUTTON_EVENTS[state.buttonevent], state: state

  checkSensors: (callback=->) =>
    @verify (error) =>
      return callback error if error?
      requestOptions =
        method: 'GET'
        uri: @getUrl "/api/#{@username}/sensors"
        json: true
      debug 'retrieving sensors', requestOptions
      request requestOptions, @handleResponse(callback)

module.exports = Hue