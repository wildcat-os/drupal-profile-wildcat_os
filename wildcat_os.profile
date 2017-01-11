<?php

/**
 * @file
 * Defines the Wildcat install screen by modifying the install form.
 *
 * Inspired by lightning.profile in drupal/lightning.
 * @see http://cgit.drupalcode.org/lightning/tree/lightning.profile?h=8.x-2.x
 */

use Drupal\Core\Link;
use Drupal\Core\Url;

/**
 * Implements hook_install_tasks().
 */
function wildcat_os_install_tasks(&$install_state) {
  $has_required = !empty($install_state['wildcat_os_flavor']['modules']['require']);
  $has_recommended = !empty($install_state['wildcat_os_flavor']['modules']['recommend']);
  $require_title =  t('Add some flavor');
  $recommend_title = $has_required ? t('Add some more flavor') : $require_title;

  return [
    'wildcat_os_get_flavor' => [
      'display' => FALSE,
    ],
    'wildcat_os_install_required_modules' => [
      'display_name' => $require_title,
      'display' => $has_required,
      'run' => $has_required ? INSTALL_TASK_RUN_IF_NOT_COMPLETED : INSTALL_TASK_SKIP,
      'type' => 'batch',
    ],
    'wildcat_os_install_recommended_modules' => [
      'display_name' => $recommend_title,
      'display' => $has_recommended,
      'run' => $has_recommended ? INSTALL_TASK_RUN_IF_NOT_COMPLETED : INSTALL_TASK_SKIP,
      'type' => 'batch',
    ],
    'wildcat_os_install_themes' => [
      'display' => FALSE,
    ],
  ];
}

/**
 * Implements hook_install_tasks_alter().
 */
function wildcat_os_install_tasks_alter(array &$tasks, $install_state) {
  // We do not know the themes yet when Drupal wants to install them, so we need
  // to do this later.
  $tasks['install_profile_themes']['run'] = INSTALL_TASK_SKIP;
  $tasks['install_profile_themes']['display'] = FALSE;


  if (isset($install_state['wildcat_os_flavor']['post_install_redirect'])) {
    // Use a custom redirect callback, in case a custom redirect is specified.
    $tasks['install_finished']['function'] = 'wildcat_os_redirect';
    $tasks['install_finished']['display_name'] = 'Install complete';
    $tasks['install_finished']['display'] = TRUE;
  }

  // Install flavor modules and themes immediately after profile is installed.
  $sorted_tasks = [];
  $require_key = 'wildcat_os_install_required_modules';
  $recommend_key = 'wildcat_os_install_recommended_modules';
  $theme_key = 'wildcat_os_install_themes';
  foreach ($tasks as $key => $task) {
    if (!in_array($key, [$require_key, $recommend_key, $theme_key])) {
      $sorted_tasks[$key] = $task;
    }
    if ($key === 'install_install_profile') {
      $sorted_tasks[$require_key] = $tasks[$require_key];
      $sorted_tasks[$recommend_key] = $tasks[$recommend_key];
      $sorted_tasks[$theme_key] = $tasks[$theme_key];
    }
  }
  $tasks = $sorted_tasks;
}

/**
 * Install task callback.
 *
 * Collects the flavor information.
 *
 * @param array $install_state
 *   The current install state.
 */
function wildcat_os_get_flavor(array &$install_state) {
  /** @var \Drupal\wildcat_os\WildcatOsFlavorInterface $flavor */
  $flavor = \Drupal::service('wildcat_os.flavor');
  $install_state['wildcat_os_flavor'] = $flavor->get();
}

/**
 * Install task callback.
 *
 * Installs flavor required modules via a batch process.
 *
 * @param array $install_state
 *   An array of information about the current installation state.
 *
 * @return array
 *   The batch definition.
 */
function wildcat_os_install_required_modules(array &$install_state) {
  if (empty($install_state['wildcat_os_flavor']['modules']['require'])) {
    return [];
  }

  $modules = $install_state['wildcat_os_flavor']['modules']['require'];

  $batch = _wildcat_os_install_modules($modules, $install_state);
  $batch['title'] = t('Adding flavor: installing required modules');

  return $batch;
}

/**
 * Install task callback.
 *
 * Installs flavor recommended modules via a batch process.
 *
 * @param array $install_state
 *   An array of information about the current installation state.
 *
 * @return array
 *   The batch definition.
 */
function wildcat_os_install_recommended_modules(array &$install_state) {
  if (empty($install_state['wildcat_os_flavor']['modules']['recommend'])) {
    return [];
  }

  $modules = $install_state['wildcat_os_flavor']['modules']['recommend'];

  $batch = _wildcat_os_install_modules($modules, $install_state);
  $batch['title'] = t('Adding flavor: installing recommended modules');

  return $batch;
}

/**
 * Returns the batch definitions for the module install task callbacks.
 *
 * Installs flavor modules via a batch process.
 *
 * @param array $modules
 *   An array of modules that either required or recommended for this flavor.
 * @param array $install_state
 *   An array of information about the current installation state.
 *
 * @return array
 *   The batch definition.
 *
 * @see wildcat_os_install_required_modules()
 * @see wildcat_os_install_recommended_modules()
 * @see install_profile_modules()
 */
function _wildcat_os_install_modules(array $modules, &$install_state) {
  if (empty($modules)) {
    return [];
  }

  $installed_modules = \Drupal::config('core.extension')->get('module') ?: [];
  // Do not pass on already installed modules.
  $modules = array_filter($modules, function($module) use ($installed_modules) {
    return !isset($installed_modules[$module]);
  });
  \Drupal::state()->set('install_profile_modules', $modules);

  return install_profile_modules($install_state);
}

/**
 * Install task callback.
 *
 * Install themes and sets theme settings.
 *
 * @param array $install_state
 *   The current install state.
 */
function wildcat_os_install_themes(array &$install_state) {
  $theme_admin = $install_state['wildcat_os_flavor']['theme_admin'];
  $theme_default = $install_state['wildcat_os_flavor']['theme_default'];
  if (!empty($theme_admin) || !empty($theme_default)) {
    $theme_config = \Drupal::configFactory()->getEditable('system.theme');

    if (!empty($theme_admin)) {
      $install_state['profile_info']['themes'][] = $theme_admin;
      $theme_config->set('admin', $theme_admin);
    }

    if (!empty($theme_default)) {
      $install_state['profile_info']['themes'][] = $theme_default;
      $theme_config->set('default', $theme_default);
    }

    $theme_config->save(TRUE);
    install_profile_themes($install_state);
  }

  if (\Drupal::moduleHandler()->moduleExists('node')) {
    \Drupal::configFactory()->getEditable('node.settings')
      ->set('use_admin_theme', TRUE)
      ->save(TRUE);
  }
}

/**
 * Install task callback.
 *
 * Redirects the user to a particular URL after installation.
 *
 * @param array $install_state
 *   The current install state.
 *
 * @return array
 *   A renderable array with a success message and a redirect header, if the
 *   extender is configured with one.
 */
function wildcat_os_redirect(array &$install_state) {
  $redirect = $install_state['wildcat_os_flavor']['post_install_redirect'];
  $redirect['path'] = "internal:/{$redirect['path']}";
  $proceed_text = t('You can proceed to your site now');
  $proceed_url = Url::fromUri($redirect['path'], $redirect['options']);
  // Explicitly set the base URL, if not previously set, to prevent weird
  // redirection snafus.
  if (empty($proceed_url->getOption('base_url'))) {
    $proceed_url->setOption('base_url', $GLOBALS['base_url']);
  }
  $proceed_url->setAbsolute(TRUE);
  $proceed = Link::fromTextAndUrl($proceed_text, $proceed_url)->toString();

  return [
    '#title' => t('Start organizing!'),
    'info' => [
      '#prefix' => '<p>',
      '#suffix' => '</p>',
      '#markup' => t('Your site is ready to go! @proceed.', [
        '@wildcat' => 'Wildcat-flavored',
        '@proceed' => $proceed,
      ]),
    ],
  ];
}
