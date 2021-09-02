'''
Given a file that has been read (and saved) through read_in_data.py, create and save a UMAP supervised fitter based on the provided file. 
Unfortunately very slow because the fitter takes significant time to converge.
'''

import numpy as np
from sklearn.neural_network import MLPClassifier
from sklearn.metrics import confusion_matrix
import os, pickle, umap

# Where is the data stored?
os.chdir(r'./')

# Which file are we reading?
filename = '2018_03_15_0013'

# File with original data
filename_abf = filename + '.abf'

# File with hand-coded bursts
filename_burst = filename + '_vr_bursts.txt'
partial_filename = filename + '_partial_dt_'

# Get all files and filter for those that are training files
fls = list(os.walk(os.getcwd()))[0][2]
fls = np.array(fls)
fls = fls[[partial_filename in x for x in fls]]
fls = fls[['umap' not in x for x in fls]]

# Use the first as training data
training = np.load(fls[0])
ys_training = training[:,-1]

# Fit data
fitter  = umap.UMAP(n_neighbors=30, min_dist=0, n_components=15)
fitter  = fitter.fit(training[:, 1:-2], y = ys_training)

with open(f'{filename}_fitter.pkl', 'wb') as fl:
    pickle.dump(fitter, fl)

# Save estimated fitter for future reference
with open(f'{filename}_fitter.pkl', 'rb') as fl:
    fitter = pickle.load(fl)

# fit to data
training_2d = fitter.transform(training[:, 1:-2])

# We add time, visual stimuli and outcome to the training data we save
training_2d_to_save = np.hstack((np.reshape(training[:,0], (training.shape[0], 1)), training_2d))
training_2d_to_save = np.hstack((training_2d_to_save, np.reshape(training[:,-2], (training.shape[0], 1))))
training_2d_to_save = np.hstack((training_2d_to_save, np.reshape(training[:,-1], (training.shape[0], 1))))

# Save training set for future reference
np.save(f'{filename}_training_set.npy', training_2d_to_save)
training_2d_to_save = np.load(f'{filename}_training_set.npy')

# Load the outcome
ys_training = training_2d_to_save[:,-1]

# We leave the visual stimulus but take out the time
training_2d = training_2d_to_save[:,1:-1]
del training_2d_to_save

# confusion matrix
overall_cm = np.zeros((2, 2))

# Check how the training is doing
clf = MLPClassifier(solver='adam', alpha=0.1, hidden_layer_sizes=(5, 3), random_state=12341234)
clf.fit(training_2d, ys_training.flatten())
preds = clf.predict(training_2d)
print(confusion_matrix(ys_training, preds))

